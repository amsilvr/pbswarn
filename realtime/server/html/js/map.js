/**************************************************************
 *
 *  Copyright (c) 2018 Public Broadcasting Service
 *  Contact: <warn@pbs.org>
 *  All Rights Reserved.
 *
 *  Version 1.13 10/22/2018
 *
 *************************************************************/

var alerts;
var loaded = false;

const extreme = "#ff9999";
const severe = "#f2e765";
const moderate = "#88ffff";
const minor = "#99ff99";
const unknown = "#ffffff";

String.prototype.replaceAll = function(search, replacement) {
    return String.prototype.replace(new RegExp(search, 'g'), replacement);
};

const smallScreen = () => {
    w = $(window).width()
    if ( w < 1050) {
        return true
    } else {
        return false
    } 
}

//////////////////////////////////////////////////////
// Local Storage
//////////////////////////////////////////////////////

// try to retrieve saved view parameters from LocalStorage
const resetView = evt => {
    try {
        mbdict = JSON.parse(localStorage.defaultBounds)
        var swLatLng = L.latLng([mbdict["_southWest"]["lat"],mbdict["_southWest"]["lng"]])
        var neLatLng = L.latLng([mbdict["_northEast"]["lat"],mbdict["_northEast"]["lng"]])
        mbounds = L.latLngBounds(swLatLng, neLatLng)
        map.fitBounds(mbounds)
    } catch {}
}

const setDefaultViewToCurrent = () => {
    $.confirm({
        title: '',
        backgroundDismiss: true,
        content: 'Save current map view as default?',
        boxWidth: '15%',
        useBootstrap: false,
        buttons: {
            Yes: function () {
                localStorage.defaultBounds = JSON.stringify(map.getBounds())
            },
            No: function () { },
        }
    });
}

//////////////////////////////////////////////////////
// Scroll Viewer
//////////////////////////////////////////////////////

var tt_running = false;
var typed;
const hold = 3000;
var messageArray;
var messagePointer = 0;

const consoleBG = document.getElementById('console_bg');
const consoleWindow = document.getElementById('console_window');
const consoleText = document.getElementById('console_text');
const tableBG = document.getElementById('table_window');
const tableDisp = document.getElementById('table_display');
var displayWindow;

const hideScroll = () => {
    consoleBG.style.display = "none";
    $('#scrollBtn').html('Scanner');
    haltTT();
}

const showScroll = () => {
    consoleBG.style.display = "block";
    tableDisp.style.display = "none";
    $('#scrollBtn').html('Scanner Off');
}

const isLoaded = () => {
    if (typeof(alerts) != "undefined") { return true }
    return false;
}

// button click to show/hide the Scroller
$('#scrollBtn').click(function(){
  if (consoleBG.style.display == "block") {
      hideScroll()
  } else {
      consoleBG.style.display="block"
      showScroll()
      runTT()
  }
})

const updateScroll = () => { // called when new data arrives
    // if we're not actively typing, if scroll is visible, restart the scroll
    if ( typeof(typed) == "undefined") {
        messagePointer = 0;
        if (consoleBG.style.display == "block") {
            runTT();
        }
    }
}

// type the next alert in rotation in sliding div id="console_text"
const runTT = () => {
    if (alerts.length > 0) {
        if (messagePointer >= alerts.length) {
             messagePointer = 0;
        }
        alert = alerts[messagePointer]
        showScroll();
        focusOn(alert)
        consoleBG.style.backgroundColor = "#ffffffaa"
        typeAlert(alert)
        messagePointer++
    } else {
        // if no alerts, hide the scroll background, reset the button and view
        $("#msgId").html("No alerts")
        consoleBG.style.backgroundColor="transparent"
        msgId.style.backgroundColor = "#fff";
        //$('#scrollBtn').html("Scanner")
        msgId.style.display="block"
        resetView()
    }
}

const typeAlert = alert => {  // launches runTT() again when complete
    if (typeof(typed) != "undefined") {  // kill any still-running typer
        typed.destroy();
    }
    consoleText.textContent = ""
    $("#msgId").html("Alert " + (messagePointer + 1) + " of " + alerts.length)
    clr = getColor(alert) + "aa"
    $("#msgId").css("background-color", clr)
    typed = new Typed(consoleText, {
        strings: [make_text(alert)],
        typeSpeed: 10,
        showCursor: false,
        fadeOut: true,
        fadeOutDelay:hold,
        startDelay: 250,
        loop: false,
        onComplete: function(self) {
            setTimeout(function(){
                typed.destroy();
                $("#console_text").css('top',0)
                runTT()
            },
            2000)
        }
    })
}

// format the alert contents for the console or table display
const make_text = alert => {
    var sent = alert.Sent
    sent = sent.replace("T"," at ")
    // Now build the html
    var text = ""
    var warning = ""
    if (alert.Status == "Test") { warning = "*** TEST MESSAGE ***" }
    if (alert.Status == "Exercise") { warning = "*** EXERCISE MESSAGE ***" }
    if (alert.Headline !=null && alert.Headline.length > 0) {
        heading = alert.Headline
    } else {
        heading = alert.Cmam
    }
    ad = alert.AreaDesc
    if (warning != "") { text = "<p>${warning}</p>"}
    text += `
<small>${alert.Source}</small><br>
<font size='-2'>${sent}</font>
<p><font size="+1">${heading}</font></p>
<small>
<p> ${alert.Levels} - ${alert.ResponseType}</p>
<p>WEA Text: <i>${alert.Cmam}</i></p>
</small>
<p>${alert.Description}</p>
<p>${alert.Instruction}</p>
<p>Area: ${ad}</p>
<small><p>Expires: ${alert.Expires.replace('T',' ')}</p></small>
<font size='-2'><p>Ref: ${alert.ID} </p></font><br>
            `
    if (warning != "") { text += "<p>${warning}</p>"}
    return text;
}

const isCurrent = item => {  // true if not expired
    expString = item.Expires
    exp = new Date(expString)
    zExp = new Date(exp.toISOString()).toISOString()
    now = new Date(new Date().toUTCString().substr(0, 25))
    if (now > zExp) {
        return false
    } else {
        return true
    }
}

// interval-driven function to scroll up text as needed
const scrollUp = () => {
    var windowHeight = parseInt($("#console_window").height())
    var textHeight = parseInt($("#console_text").height())
    var offset = parseInt(windowHeight - textHeight)
    if (offset < 0) {
        $("#console_text").css('top', offset)
    } else {
        $("#console_text").css('top',0)
    }
}
var youInterval = setInterval(scrollUp, 200)

// on console close, stop the typewriter
const haltTT = () => {
    tt_running = false;
    if (typeof(typed) != "undefined") {
        typed.destroy()
    }
    $("#console_text").css('top',0)
}

const scanVisible = () => {
    if (consoleBG.style.display = "block") {
        return true
    } else {
        return false
    }
}

//if ( !loaded ) { showScroll() }
//loaded = true;

//////////////////////////////////////////////////////
// Tabular Viewer
//////////////////////////////////////////////////////

const hideList = () => {
    tableBG.style.display = "none"
    tableDisp.style.display = "none"
    $('#tableBtn').html('List')
}

const showList = () => {
    if (typeof(alerts) != "undefined") {
        if (alerts.length > 0) {
            tableBG.style.display = "block"
            $('#tableBtn').html('Hide List')
        } else {
            tableBG.style.display = "none"
            console.log("List Hidden, no alerts")
        }
    }
}

const itemVisible = () => {
    if (tableDisp.style.display = "block") {
        return true
    } else {
        return false
    }
}

const listVisible = () => {
    if (tableBG.style.display = "block") {
        return true
    } else {
        return false
    }
}

// button click to toggle the table viewer
$('#tableBtn').click(function(){
    if (tableBG.style.display == "block") {
        hideList()
    } else {
        showList()
    }
});

// once we have data, set up the table
var tableLoaded = false;
var dataTable;
const updateTable = () => {
    if (!tableLoaded) {  // if startup, init dataTable
        if (!smallScreen()) {
            showList()
        }
        tableLoaded = true;
        dataTable = $('#table').DataTable( {
            data: alerts,
            paging: false,
            info:false,
            fixedHeader: {
                header: false,
                footer: true
            },
            searching: false,
            order: [],
            columns: [
                { render: function (data, type, row) {
                        slug = row.Headline;
                        if (slug == "") { slug =  row.Cmam; }
                        if (slug.length > 80) { slug = slug.substring(0,77) + "..." }
                        snt = row.Sent.replace("T", " at ");
                        response = row.ResponseType;
                        if (response == "") { response = "Alert"}
                        severity = row.Levels.split("/")[1];
                        if (severity == "") { severity="Unknown"}
                        color = getColor(row)
                        cell = `
<div class="${severity }">
<div><span class="response">${response}</span>
<span class="headline">${slug} </span></div>
<div class="origin">From ${row.Source} on ${snt}</div></div>
                                `
                        return cell
                    }
                }
            ]
        });
        // set click handler on table row
        $('#table').on('click', 'tr', function () {
            var item = dataTable.row( this ).data()
            // zoom the map to (aggregate) bounds of the alert's polys
            if (typeof(typed) != "undefined") {
                focusOn(item)
                polygons = item.Polygons
                display( item )
            }
        } );
    } else {  // existing dataTable, reload latest data
        dataTable.clear()
        dataTable.rows.add(alerts)
        dataTable.draw()
    }
}

// get the severity-based color value for an alert
const getColor = item => {
    sev = item.Levels.split("/")[1]
    if (sev.includes("Extreme")) {
        return extreme
    } else if (sev.includes("Severe")) {
        return severe
    } else if (sev.includes("Moderate")) {
        return moderate
    } else if (sev.includes("Minor")) {
        return minor
    } else {
        return unknown
    }
}

const display = item => {
    // hide the Scroller
    hideScroll();
    // and show the selected alert in the display space
    tableDisp.style.display = "block"
    $("#table_display").html(make_text(item))
    $("#table_display").css("background-color", getColor(item)+"aa")
}

const tableTextHide = () => {
    tableDisp.style.display = "none"
}

//////////////////////////////////////////////////////
// Realtime Map
//////////////////////////////////////////////////////

// set up the map, use stored view if any
var centerLat, centerLon, defaultZoom
var map = L.map('map',zoomDelta=0.1).setView([39.833, -98.583], 4.2)
if (localStorage.defaultBounds) {
    resetView();
}
var center;
// load colored pins for severity indication
var extremeIcon = L.icon({
    iconUrl: 'img/extremeIcon.png',
    iconSize: [18,18],
    iconAnchor: [9,18],
    popupAnchor: [18,9]
});
var severeIcon = L.icon({
    iconUrl: 'img/severeIcon.png',
    iconSize: [18,18],
    iconAnchor: [9,18],
    popupAnchor: [18,9]
});
var moderateIcon = L.icon({
    iconUrl: 'img/moderateIcon.png',
    iconSize: [18,18],
    iconAnchor: [9,18],
    popupAnchor: [18,9]
});
var minorIcon = L.icon({
    iconUrl: 'img/minorIcon.png',
    iconSize: [18,18],
    iconAnchor: [9,18],
    popupAnchor: [18,9]
});
var unknownIcon = L.icon({
    iconUrl: 'img/unknownIcon.png',
    iconSize: [18,18],
    iconAnchor: [9,18],
    popupAnchor: [18,9]
});

// add the base map from OSM tile server
L.tileLayer('http://{s}.tile.osm.org/{z}/{x}/{y}.png', {
    attribution: 'Map &copy; <a href="http://osm.org/copyright">OpenStreetMap</a> contributors | Wireless Emergency Alerts from PBS WARN @ KVIE, Sacramento\n'
}).addTo(map);

var markerGroup = L.layerGroup().addTo(map)
var polyGroup = L.layerGroup().addTo(map)

// plot an alert on the map
const plot = alert => {
    var popup = make_text(alert)
    tiptext = alert.Cmam
    if (tiptext == '') {
        tiptext = alert.Headline
    }
    polygons = alert["Polygons"];
    color = getColor(alert);
    if (polygons.length > 0) {  // if there's no polygon by now, skip plotting
        for (var i = 0; i<polygons.length; i++) {
            plot_polygon(polygons[i], color, alert)
        }
        var label = alert["ResponseType"]
        if (label == "") { abel = "Alert"  }
        if (alert.Status == "Test") { label = "TEST" }
        if (alert.Status == "Exercise") { label = "EXERCISE" }
        // style icon and label per alert severity
        sev = alert.Levels.split("/")[1]
        iClass = "alertIconUnknown"
        icon = "unknownIcon"
        if (sev.includes("Extreme")) { iClass = "alertIconExtreme"; icon = extremeIcon }
        if (sev.includes("Severe")) { iClass = "alertIconSevere"; icon = severeIcon}
        if (sev.includes("Moderate")) {iClass = "alertIconModerate"; icon = moderateIcon}
        if (sev.includes("Minor")) {iClass = "alertIconMinor"; icon = minorIcon}
        var myIcon = L.divIcon({className: iClass, iconSize: null, html: label})
        var label = L.marker( center, {icon: myIcon}).addTo(map).addTo(markerGroup)
        marker = L.marker(center, {icon: icon}).addTo(map).addTo(markerGroup)
        marker.addEventListener("click", function(event) {
            display(alert)
            focusOn(alert)
        })
        label.addEventListener("click", function(event) {
            display(alert)
            focusOn(alert)
        })
        marker.bindTooltip(tiptext);
    }
}

// get center point of supplied alert
const getCenterOf = item => {
    var bounds = make_bounds(item.Polygons[0])
    for (var i=1;i<item.Polygons.length; i++) {
        bounds.extend( make_bounds(item.Polygons[i]) )
    }
   return L.LatLng([bounds.centerLat, bounds.centerLon])
}

// translate CAP polygon to Leaflet polygon object
const plot_polygon = (polygon, color, alert) => {
    new_polygon = []
    var lat, lon
    if (typeof(polygon) == "string") { // if polygon is a new-style string
        points = polygon.split(" ")
        for (var i=0;i<points.length;i++) {
            var point = points[i]
            splitp = point.split(",")
            lat = splitp[0]
            lon = splitp[1]
            point = [parseFloat(lat),parseFloat(lon)]
            new_polygon.push(point )
        };
    } else {
        points = polygon;
        for (var j = 0; j<points.length; j++) {
            lat = points[j][0]
            lon = points[j][1]
            new_polygon.push(L.latLng(lat, lon ))
        }
    }
    thisPoly = L.polygon(new_polygon, {
                            color: color,
                            fillOpacity: 0.4,
                            opacity: 0.8,
                        }).addTo(map).addTo(polyGroup);
    thisPoly.on("click", function(event) { display(alert); })
    center = thisPoly.getCenter()  // coordinates for icon
    return thisPoly
}

// create a Leaflet LatLngBounds object from a CAP-format (lat,lon lat,lon...) polygon string
const getBounds = polygon => {
    var new_poly = []
    points = polygon.split(" ")
    for(var i = 0; i<points.length; i++)  {
        point = points[i]
        here = L.latLng(point.split(","))
        new_poly.push(here)
    }
    return L.polygon(new_poly).getBounds()
}

// get aggregate bounds of all polys in an item
const itemBounds = item => {
    var bounds = getBounds(item.Polygons[0])
    for (var i=1;i<item.Polygons.length; i++) {
        bounds.extend( getBounds(item.Polygons[i]) )
    }
    return bounds
}

// get aggregate bounds of all items in alerts
const allBounds = alerts => {
    if (typeof(alerts) != 'undefined') {
        var abounds = itemBounds(alerts[0]);
        if (alerts.length > 1) {
            for (var i=1;i<alerts.length; i++) {
                abounds.extend(itemBounds(alerts[i]))
            }
        }
        return abounds
    } else {
        return null
    }
}

// zoom the map to feature the selected JSON alert
const focusOn = item => {
    if (typeof(item) != "undefined") {
        bounds = itemBounds(item)
        // if scanner or list text visible, shift the map center to a better spot on the screen
        if (scanVisible) {
            map.fitBounds(shiftBounds(bounds).pad(0.3))
        }
    }
}

const shiftBounds = bounds => {
    s = bounds.getSouth()
    w = bounds.getWest()
    n = bounds.getNorth()
    e = bounds.getEast()
    oLat = (n-s)/4
    oLon = (w-e)/1.5
    return L.latLngBounds(L.latLng(s-oLat, w+oLon), L.latLng(n-oLat, e+oLon))
}

// clear the map
const clearMap = () => {
    markerGroup.clearLayers()
    polyGroup.clearLayers()
}
    
//////////////////////////////////////////////////////
// Data Feed from server
//////////////////////////////////////////////////////
const poll = () => {
    try {
    $.ajax({
      url: "http://warn.pbs.org/alerts.json",
      data: "",
      success: success,
      error: success,
      dataType: "text/XML"
    })
    } catch(e) {
        console.log("server poll failed: " + e)
    }
}

// handle arrival of new JSON data from server
const success = data => {
    clearMap();
    try {
        j = JSON.parse(data.responseText)
    } catch {
        return;
    }
    $('#hb').html("Link up " + moment(j.heartbeat).format("YYYY-MM-DD HH:mm:ss") + " UTC")
    alerts = j.alerts
    // tell dataTable and scroller to update (from global 'alerts' object)
    updateTable()
    updateScroll()
    var i=0, item;
    while(item = alerts[i++]) {
        if (isCurrent(item)) {  
            plot(item)
        } 
    }
    if (!loaded && smallScreen()) {
        map.fitBounds(allBounds(alerts).pad(0.3))
    }
    loaded = true;
}

// initial poll and set up interval
$(document).ready(function () {
    if (smallScreen()) {
        hideScroll()
        hideList()
        console.log("Small Screen")
    } else {
        showScroll()
        showList()
    }
    poll()
    setInterval(poll, 10000)
});

// when map regains screen focus, poll the alerts data immediately
$(window).bind('focus', function() {
    poll()
});
