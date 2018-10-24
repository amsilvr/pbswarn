/**************************************************************
 *
 *  Copyright (c) 2018 Public Broadcasting Service
 *  Contact: <warn@pbs.org>
 *  All Rights Reserved.
 *
 *  Version 1.13 10/22/2018
 *
 *************************************************************/

var Client = require('mariasql'),
    xml2js = require('xml2js'),
    util = require('util'),
    fs = require('fs')

var c = new Client({
	host: '192.168.2.1',
	user: 'warn',
	password: "warn"
})

var parser = new xml2js.Parser()

const jDump = json => {
  console.log(util.inspect(json, false, null))
}

var heartbeatQuery = c.prepare('select time from warn.updated where ID = 1')
var currentAlertQuery = c.prepare('select xml from warn.alerts where (unix_timestamp(expires) > unix_timestamp(utc_timestamp())) and replacedBy is null order by received desc')
var polygonQuery = c.prepare('select polygon from warn.fips where samecode = :geocode')

// get currently non-expired alerts, parse and process each as JSON
const update = () => {

  let ajax = {heartbeat:'', alerts:[]}

  // look up heartbeat and include in ajax
  c.query(heartbeatQuery(), null, { useArray: false }, function(err, rows) {
    if (err) throw err
    ajax.heartbeat = rows[0].time
  })
  
  c.query(currentAlertQuery(), null, { useArray: false }, function(err, rows) {
    if (err) throw err
    var capJson
    rows.forEach(function(capAlert) {
      parser.parseString(capAlert.xml, function (err, result) {
        capJson = result.alert
      })
      //process an alert
      jDump(capJson)
      let alert = {}
      capJson.info.forEach(function(info) {
        let item = {}
        item.ID = capJson.identifier[0]
        item.Sender = capJson.sender[0]
        item.Sent = capJson.sent[0]
        item.Status = capJson.status[0]
        item.MsgType = capJson.msgType[0]
        if (typeof(info.cmam) != "undefined") {
          item.Cmam = info.cmam
        }
        if (typeof(info.headline) != "undefined") {
          item.Headline = info.headline[0]
        }
        if (typeof(info.senderName) != "undefined") {
          item.Source = info.senderName[0]
        }
        item.Levels = info.urgency + " / " + info.severity + " / " + info.certainty
        item.ResponseType  = info.responseType[0]
        item.Description = info.description
        item.Instruction = info.instruction[0]
        item.Expires = info.expires[0]
        // these following will be aggretated from multiple Area blocks if present
        item.AreaDesc = ""
        item.Polygons = []
        item.Circles = []
        item.Geocodes = []
        // for each area block, add its values to info-level arrays
        info.area.forEach(function(area){
          item.AreaDesc += area.areaDesc + " "
          if (typeof(area.polygon) != 'undefined') {
            area.polygon.forEach(function(poly) {
              console.log(poly)
              item.Polygons.push(poly)
            })
          }
          try { // frequently there are no circles in source
            area.circle.forEach(function(circ) {
              item.Circles.push(circ)
            })
          } catch (e) {}
          area.geocode.forEach(function(geo){
            item.Geocodes.push(geo)
          })
        })
        // if there are no polygons in the source, look up any geocodes and add to Polygons[]
        //item.Polygons.length = 0 // uncomment to force polygon substitution
        if (item.Polygons.length == 0) {
          item.Geocodes.forEach(function(geocode){
            if (geocode.valueName == "SAME") {
              var code = geocode.value[0]
              c.query(polygonQuery({geocode:code}), function( err, rows) {
                if (err) throw err
                var poly = rows[0].polygon
                item.Polygons.push(poly.replace(/['"]+/g, '')) // lose extraneous quote marks from FIPS db
              })
            }
          })
        }
        // push each item to the 'ajax' return object
        ajax.alerts.push(item)
      })
    })
  })
  c.end()
  // after a moment to inject remedial polys, publish the Ajax object to the server
  setTimeout(function() {
    //console.log(JSON.stringify(ajax))
    fs.writeFile("/var/www/html/new_alerts.json", JSON.stringify(ajax), function(err){if (err) throw err})
  }, 
  1000)
}
/**************************************************************
 *
 *  Copyright (c) 2018 Public Broadcasting Service
 *  Contact: <warn@pbs.org>
 *  All Rights Reserved.
 *
 *  Version 1.13 10/22/2018
 *
 *************************************************************/

var Client = require('mariasql'),
    xml2js = require('xml2js'),
    util = require('util'),
    fs = require('fs')

var c = new Client({
	host: '192.168.2.1',
	user: 'warn',
	password: "warn"
})

var parser = new xml2js.Parser()

const jDump = json => {
  console.log(util.inspect(json, false, null))
}

var heartbeatQuery = c.prepare('select time from warn.updated where ID = 1')
var currentAlertQuery = c.prepare('select xml from warn.alerts where (unix_timestamp(expires) > unix_timestamp(utc_timestamp())) and replacedBy is null order by received desc')
var polygonQuery = c.prepare('select polygon from warn.fips where samecode = :geocode')

// get currently non-expired alerts, parse and process each as JSON
const update = () => {

  let ajax = {heartbeat:'', alerts:[]}

  // look up heartbeat and include in ajax
  c.query(heartbeatQuery(), null, { useArray: false }, function(err, rows) {
    if (err) throw err
    ajax.heartbeat = rows[0].time
  })
  
  c.query(currentAlertQuery(), null, { useArray: false }, function(err, rows) {
    if (err) throw err
    var capJson
    rows.forEach(function(capAlert) {
      parser.parseString(capAlert.xml, function (err, result) {
        capJson = result.alert
      })
      //process an alert
      //jDump(capJson)
      let alert = {}
      capJson.info.forEach(function(info) {
        let item = {}
        item.ID = capJson.identifier[0]
        item.Sender = capJson.sender[0]
        item.Sent = capJson.sent[0]
        item.Status = capJson.status[0]
        item.MsgType = capJson.msgType[0]
        if (typeof(info.cmam) != "undefined") {
          item.Cmam = info.cmam
        } else {
          item.Cmam = "[none]"
        }
        if (typeof(info.headline) != "undefined") {
          item.Headline = info.headline[0]
        } else {
          item.Headline = ""
        }
        if (typeof(info.senderName) != "undefined") {
          item.Source = info.senderName[0]
        } else {
          item.Source = ""
        }
        item.Levels = info.urgency + " / " + info.severity + " / " + info.certainty
        item.ResponseType  = info.responseType[0]
        if (typeof(info.description) != "undefined") {
          item.Description = info.description
        } else {
          item.Description = ""
        }
        item.Instruction = info.instruction[0]
        item.Expires = info.expires[0]
        // these following will be aggretated from multiple Area blocks if present
        item.AreaDesc = ""
        item.Polygons = []
        item.Circles = []
        item.Geocodes = []
        // for each area block, add its values to info-level arrays
        info.area.forEach(function(area){
          item.AreaDesc += area.areaDesc[0] + " "
          if (typeof(area.polygon) != 'undefined') {
            area.polygon.forEach(function(poly) {
              console.log(poly)
              item.Polygons.push(poly)
            })
          }
          try { // frequently there are no circles in source
            area.circle.forEach(function(circ) {
              item.Circles.push(circ)
            })
          } catch (e) {}
          area.geocode.forEach(function(geo){
            item.Geocodes.push(geo)
          })
        })
        // if there are no polygons in the source, look up any geocodes and add to Polygons[]
        //item.Polygons.length = 0 // uncomment to force polygon substitution
        if (item.Polygons.length == 0) {
          item.Geocodes.forEach(function(geocode){
            if (geocode.valueName == "SAME") {
              var code = geocode.value[0]
              c.query(polygonQuery({geocode:code}), function( err, rows) {
                if (err) throw err
                var poly = rows[0].polygon
                item.Polygons.push(poly.replace(/['"]+/g, '')) // lose extraneous quote marks from FIPS db
              })
            }
          })
        }
        // push each item to the 'ajax' return object
        ajax.alerts.push(item)
      })
    })
  })
  c.end()
  // after a moment to inject remedial polys, publish the Ajax object to the server
  setTimeout(function() {
    //console.log(JSON.stringify(ajax))
    fs.writeFile("/var/www/html/alerts.json", JSON.stringify(ajax), function(err){if (err) throw err})
  }, 
  1000)
}

update()
setInterval(update, 5000)

update()
setInterval(update, 5000)
