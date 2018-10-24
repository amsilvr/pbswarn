package catcher

import (
    "bytes"
    "database/sql"
    "encoding/xml"
    //"encoding/hex"
    "fmt"
    "hash"
    "io"
    "log"
    "net"
    "strings"
    "time"

    "github.com/dmichael/go-multicast/multicast"
    cap "github.com/mark-adams/cap-go/cap"
)

var (
    inMessage bool
    message   []byte
    breaker   []byte
    lastHash  string
    replacer  strings.Replacer
    h         hash.Hash
    db        *sql.DB
    err       error
    result    sql.Result
    rows      *sql.Rows
    dispPoly  string
    channel   chan []byte
)

const (
    defaultMulticastAddress = "224.3.0.1:5000"
    dsn                     = "warn:warn@tcp(192.168.2.1:3306)/WARN"
)

type mapItem struct {
    ID           string
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
    Polygons     string
}

// Run is a goroutine to monitor UDP packets from the WARN receiver and
// re-assemble
func Run(ch chan []byte) {
    channel = ch
    inMessage = false
    replacer = *strings.NewReplacer("&#xA;", "\n")
    breaker = []byte{0x47, 0x09, 0x11} // Start of MPEG Packet break?
    // set up the UDP monitor
    fmt.Printf("Listening to %s at %s\n", defaultMulticastAddress, time.Now().Format(time.RFC1123))
    multicast.Listen(defaultMulticastAddress, packetHandler)
}

// process each multicast packet, pass along those for assembly
func packetHandler(src *net.UDPAddr, n int, b []byte) {
    msg := b[24:n]
    msg = removeAll(msg, breaker)               // take out MPEG packet breaks
    //fmt.Println(hex.Dump(msg))
    channel <- []byte("heartbeat")
    if bytes.Index(msg, []byte("CMAC")) == -1 { // skip CMAC messages
        assemble(msg)
    }
}

// filter the UDP packets and assemble XML from start to finish
func assemble(msg []byte) {
    // if packet contains "<?xml ", start a new message
    st := bytes.Index(msg, []byte("<?xml "))
    if st != -1 {
        if !inMessage {
            inMessage = true
            msg = msg[st:] // trim off leading garbage
        }
        message = make([]byte, 0) // init a new message
    }
    // if packet contains "</ale" it's the end of the message
    en := bytes.Index(msg, []byte("</ale"))
    if inMessage && en != -1 {
        msg = msg[:en]                           // trim off trailing garbage
        msg = append(msg, []byte("</alert>")...) // repair the closing tag
        message = append(message, msg...)
        inMessage = false

        // pass to monitor over channel
        channel <- message
        return
    }
    // otherwise, if we're in message, append it
    if inMessage {
        message = append(message, msg...)
    }
}

/*****************************************************
                  UTILITY FUNCTIONS
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
        log.Println(err)
        return ""
    }
    // return XML with XML-escaped newlines ("&#xA;") replaced
    return "<?xml version='UTF-8' encoding='UTF-8'?>\n" + replacer.Replace(string(cap))
}

func makeHash(text string) []byte {
    // read pretty XML into the hasher
    _, err := io.Copy(h, strings.NewReader(text))
    if err != nil {
        log.Println(err)
    }
    // and extract the result
    return h.Sum(nil)
}
