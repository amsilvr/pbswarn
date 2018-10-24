package main

import (
	"database/sql"

	_ "github.com/go-sql-driver/mysql"

	"io/ioutil"
	"log"
	"time"
)

var statement *sql.Stmt
var statement2 *sql.Stmt
var err error

func main() {
	db, err := sql.Open("mysql", "warn:warn@tcp(192.168.2.1:3306)/warn")
	check(err)
	defer db.Close()
	//statement, err = db.Prepare("select json from warn.alerts where expires > now()")
	statement, err = db.Prepare("select json from alerts where (unix_timestamp(expires) > unix_timestamp(utc_timestamp())) and replacedBy is null order by received desc")
	statement2, err = db.Prepare("select time from warn.updated where ID = 1")
	check(err)
	for {
		update()
		time.Sleep(5 * time.Second)
	}
}

func update() {
	var timestamp string
	rows, err := statement2.Query() // execute our select statement
	check(err)
	for rows.Next() {
		rows.Scan(&timestamp)
	}
	rows, err = statement.Query() // execute our select statement
	check(err)
	// extract JSON from the retrieved alerts and construct a single JSON array string
	alert := "["
	for rows.Next() {
		var json string
		rows.Scan(&json) // extract the JSON from the DB record
		alert = alert + json + ", "
	}
	if alert == "[" {
		alert = alert + "]"
	} else {
		alert = alert[0:len(alert)-2] + "]" // trim trailing ", " before closing bracket
	}
	// build heartbeat timestamp into JSON for browser
	update := "{\"heartbeat\":\"" + timestamp + "\", \"alerts\":" + alert + "}"
	// save out to AJAX data file
	err = ioutil.WriteFile("/var/www/html/alerts.json", []byte(update), 0644)
	check(err)
}

func check(e error) {
	if e != nil {
		log.Println(e)
	}
}
