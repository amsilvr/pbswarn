package main

import (
    "bytes"
    "database/sql"
    "encoding/json"
    "encoding/xml"
    "container/list"
    "hash"
    "log"
    "pbs/warn/catcher"
    "strings"
    "time"

    // mysql driver
    _ "github.com/go-sql-driver/mysql"
    cap "github.com/mark-adams/cap-go/cap"
)

var (
    inMessage   bool
    dupe       bool
    message   []byte
    breaker   []byte
    replacer  strings.Replacer
    h         hash.Hash
    db        *sql.DB
    err       error
    result    sql.Result
    rows      *sql.Rows
    dispPoly  string
    warnChannel   chan []byte
    previous = list.New()
)

const (
    defaultMulticastAddress = "224.3.0.1:5000"
    dsn                     = "warn:warn@tcp(192.168.2.1:3306)/warn"
    dedupe = 20 // number of previous messages retained for look-back when filtering out duplicates
    dupeFile = "/home/pbs/.recent.alerts"
)

type mapItem struct {
	ID           string
	Sender		 string
    Sent         string
    Status       string
    MsgType      string
    Cmam         string
    Headline     string
    Source       string
    Levels       string
    ResponseType string
    Description  string
    Instruction  string
    Expires      string
    AreaDesc     string
    Geocodes     []string
    Polygons     []string
}

func main() {
    // setup
    inMessage = false
    replacer = *strings.NewReplacer("&#xA;", "\n")
    breaker = []byte{0x47, 0x09, 0x11} // Start of MPEG Packet break?
    // set up and exercise database connection
    if db, err = sql.Open("mysql", dsn); err != nil {
        log.Fatal("Can't open database", err)
    }
    defer db.Close()
    var version string
    db.QueryRow("SELECT VERSION()").Scan(&version)
    if version == "" {
        log.Println("NO DB CONNECTION")
    } else {
        log.Println("Connected to", version)
    }
    // catcher is a goroutine that monitors the UDP source and hands back raw XML
    warnChannel = make(chan []byte)
    go catcher.Run(warnChannel) // in catcher.go
    for {
        messageProcessor(<-warnChannel) // XML as []byte
    }
}

// validates XML via Unmarshall/Marshall round trip to CAP structure from
// "github.com/mark-adams/cap-go/cap"
// also pulls aside a few details and passes them all to the database
func messageProcessor(message []byte) {

    // take out any nulls, esp at start
    bytes.Trim(message, "\x00")

    // update last link-activity time to database
    receivedTime := time.Now().UTC().Format(time.RFC3339)
    statement := `update updated set time = ? where ID = 1`
    ps, err := db.Prepare(statement)
    check(err)
    defer ps.Close()
    // execute DB statement
    _, err = ps.Exec(receivedTime)
    check (err)

    // if heartbeat message, do no more
    if bytes.Equal([]byte("heartbeat"), message) {
        return
    }

    // parse message into Alert struct per github.com/mark-adams/cap-go/cap
    var alert cap.Alert
    var uniqueID string
    var expiresTime string
    alert = parseAlert(message)
    uniqueID = alert.SenderID + "," + alert.MessageID + "," + alert.SentDate
    // if cancel or update, mark referenced earlier message in DB
    if alert.MessageType == "Cancel" {
        for replaces := range alert.ReferenceIDs {
            log.Println(replaces, " replaced by ", uniqueID)
            statement := `update alerts set replacedBy = ? where identifier = ?`
            ps, err := db.Prepare(statement)
            check(err)
            // execute DB statement
            _, err = ps.Exec(uniqueID, replaces)
            check (err)
            ps.Close()
        }
    }
    // If no Infos, it's probably a cancel, expire it immediately for display purposes
    if len(alert.Infos) == 0 {
        expiresTime = receivedTime
    } else {
        expiresTime = alert.Infos[0].ExpiresDate
    }

    // pretty-print the Alert as an XML string
    capString := toXML(alert)

    // skip if message is a duplicate of one recently received
    rows, err = db.Query("select identifier from alerts where identifier = \"" + uniqueID + "\"")
    defer rows.Close()
    if err != nil {
        log.Print("Db.Query() failed : ", err)
    } else {
        if rows.Next() {
            log.Println("DUPLICATE")
        } else {
            // send it to the database
            go toDatabase(capString, &alert, receivedTime, expiresTime)
            log.Println(alert.MessageStatus, alert.MessageType, alert.MessageID)
        }
    }
    inMessage = false // for benefit of packet scanner, go back to listening for next msg
}

/*****************************************************
          FORMAT AND STORE ALERT TO DB
*****************************************************/
// called as goroutine, goes to DB to look up polygons from FIPS if necessary,
// then stores raw XML and JSON to table Alerts
func toDatabase(capString string, alert *cap.Alert, received string, expires string) {

    var infos []cap.Info
    var info *cap.Info
    var area *cap.Area

    if &alert.Infos != nil {
        infos = alert.Infos
        if (len(infos) > 0) {
            info = &alert.Infos[0]
            if len(info.Areas) > 0 {
                area = &info.Areas[0]
            } 
        }
    } 

    // check for explicit polygon in CAP message
    var poly = ""
    if len(area.Polygon) > 0 {
        poly = area.Polygon
    }

    // FOR TEST
    //poly = ""

    var dispPoly []string
    
    // GEOCODE Mapping
    // if no polygon in received alert, look up SAME FIPS equivalent polys
    if poly == "" {
        geocodes := area.GeocodeAll("SAME")

        // FOR TEST
        //geocodes = nil
        //geocodes = append(geocodes, "000000")

        // look up polygons and add to alert

        var polygon string
        for _, gcode := range geocodes { // for each geocode in Areas[0]
            rows, err = db.Query("select polygon from fips where samecode=?", gcode)
            defer rows.Close()
            if err != nil {
                log.Print("Db.Query() failed : ", err)
            } else {
                for rows.Next() { // for each record returned for FIPS
                    err = rows.Scan(&polygon) // extract the provided polygon (if any)
                    if err != nil {
                        log.Println(err)
                    } else {
                        polygon = strings.Replace(polygon, "\"", "", 2)  // remove escaped quotes from db field
                        dispPoly = append(dispPoly, polygon)
                    }
                }
            }
        }
    } else {
        dispPoly = append(dispPoly, poly)
    }

    // build map message struct
    j := mapItem{}
	j.ID = alert.MessageID
	j.Sender = alert.SenderID
    j.Sent = alert.SentDate
    j.Status = alert.MessageStatus
    j.MsgType = alert.MessageType
    if info != nil {
        j.ResponseType = info.ResponseType
        j.Cmam = info.Parameter("CMAMtext")
        j.Headline = info.Headline
        j.Source = info.SenderName
        j.Levels = info.Urgency + " / " + info.Severity + " / " + info.Certainty
        j.Description = info.EventDescription
        j.Instruction = info.Instruction
        j.Expires = info.ExpiresDate
        if area != nil {
            j.AreaDesc = area.Description
            j.Geocodes = area.GeocodeAll("SAME")
            j.Polygons = dispPoly
        }
    }
    // serialize struct as JSON to go to database
    var jsn []byte
    if jsn, err = json.Marshal(j); err != nil {
        log.Print("json.Marshal", err.Error())
    }

    // convert received and expires times to GMT in suitable format for DB
    format := "2006-01-02T15:04:05-07:00"
    zuluSent, _ := time.Parse(format, j.Sent)
    zuluSent = zuluSent.UTC()
    zuluExpires, _ := time.Parse(format, j.Expires)
    zuluExpires = zuluExpires.UTC()

    // save XML, JSON and times to Alerts table
    // the *DB is "db"
    statement := `insert into alerts (xml, json, received, expires, identifier) values (?, ?, ?, ?, ?)`
    var ps *sql.Stmt
    if ps, err = db.Prepare(statement); err != nil {
        log.Print("warn.main Prepare", err.Error())
    }
	// execute DB statement
	uniqueID := j.Sender + "," + j.ID + "," + j.Sent
    if _, err = ps.Exec(capString, string(jsn), zuluSent, zuluExpires, uniqueID); err != nil {
        log.Print("warn.main Exec", err.Error())
    }
    ps.Close()
}

/*****************************************************
                    UTILITIES
*****************************************************/

// remove all instances of a byte slice from within another byte slice
func removeAll(source []byte, remove []byte) []byte {
    for bytes.Index(source, remove) > -1 {
        pnt := bytes.Index(source, remove)
        source = append(source[:pnt], source[pnt+12:]...)
    }
    return source
}

func parseAlert(message []byte) cap.Alert {
    alert := cap.Alert{}
    err = xml.Unmarshal(message, &alert)
    if err != nil {
        log.Println(err)
    }
    return alert
}

func toXML(alert cap.Alert) string {
    cap, err := xml.MarshalIndent(alert, "", "    ") // prettiness
    if err != nil {
        log.Print(err)
        return ""
    }
    bytes.Trim(cap, "\x00")
    // return indented XML with C18n XML-escaped newlines ("&#xA;") replaced
    return "<?xml version='UTF-8' encoding='UTF-8'?>\n" + replacer.Replace(string(cap))
}

func check(err error) {
    if err != nil {
        log.Print("warnMonitor", err.Error())
    }
}
