#### Setup ####
# if (require(tidyverse) == FALSE) {
#   install.packages("tidyverse")
# }
# 
# if (require(googlesheets) == FALSE) {
#   install.packages("googlesheets")
# }
# 
# if (require(sf) == FALSE) {
#   install.packages("sf")
# }
# 
# if (require(htmltab) == FALSE) {
#   install.packages("htmltab")
# }
# if (require(leaflet) == FALSE) {
#   install.packages("leaflet")
# }
# 
# if (require(DT) == FALSE) {
#   install.packages("DT")
# }
# 
# if (require(shiny) == FALSE) {
#   install.packages("shiny")
# }
# if (require(shinydashboard) == FALSE) {
#   install.packages("shinydashboard")
# }
# if (require(shinyjs) == FALSE) {
#   install.packages("shinyjs")
# }
# if (require(shinycssloaders) == FALSE) {
#   install.packages("shinycssloaders")
# }

library(tidyverse)
library(lubridate)
library(googlesheets)
library(htmltab)
library(sf)
library(leaflet)
library(DT)
library(shiny)
library(shinydashboard)
library(shinyjs)
library(shinycssloaders)

#### Load Data ####

if (!file.exists('data/wea_alerts.rda')) {
    source("CMAS_Clean_shiny.R", echo = FALSE)
    load_vars()
    rm(list = c("all_cmas","ss_new"), envir = .GlobalEnv)
    save.image(file = "data/wea_alerts.rda") 
} else{ 
    load(file = "data/wea_alerts.rda",verbose = FALSE)
    source("CMAS_Clean_shiny.R", echo = FALSE, verbose = FALSE)
    state_sf <<- map_states()
    counties_sf <<- map_counties()   
  }

ui <- dashboardPage(title = "WEA Distribution by County",
                    skin = "black",
        dashboardHeader(title = "WEA Alerts:"),
#
#                         h1("WARN Alerts by County"),
#         ),
        dashboardSidebar(
            h3(textOutput("type", inline = TRUE),
               "Warnings:",
               textOutput("county_name", inline = TRUE)),
            ## Date Range 
            
            # Commented out because of crashes when no alerts of a type are found

            dateRangeInput(inputId = "dateRange", label = "Date Range"
                           ,start = min(msg2$rec_time)
                           ,end = max(msg2$rec_time)
                           ,format = 'M d, yyyy'),
            ## Alert Type
            selectInput(inputId = "alertType" , label = "Alert Type"
                        ,choices = c("Total" = "Total"
                                     ,"AMBER Alert" = "AMBER"
                                     ,"Flash Flood" = "FlashFlood"
                                     ,"Hurricane" = "Hurricane"
                                     ,"Tornado" = "Tornado"
                                     ,"Other" = "Other")),

            # State selector
            selectInput(inputId = 'state', label = 'State or Region',
                        list(`Full Country` = c('Full Country','Continental US'),
                             `State` =  state_sf %>%
                                 select(NAME) %>%
                                 st_set_geometry(NULL) %>% 
                                 arrange(NAME)
                        )
            ),
            #### Instructions ####
            p("This map shows the number of Wireless Emergency Alert (WEA)
              messages transmitted between",
              ## Change the dates here to reflect the most recent alert ##
              textOutput("first_alert", inline = TRUE),
              " and ",
              textOutput("last_alert", inline = TRUE),
              " by the PBS WARN system to each county in the United States."),
            p("Please select a region or state from the menus above, or click on a county. To see a
              full list of the alerts for the selected area, see the 'List of Events' tab."),
            p("Messages are received by PBS from FEMA's IPAWS-OPEN alert
              aggregator, and then rebroadcast from every public television station in the
              country to cellular mobile service providers. This alternate path for WEA
              protects WEA messages against an internet connection failure."),
            p("This map is provided as a convenience for responders, researchers, and the public.
              It is not guaranteed to be complete or error-free. Geographic outlines reflect
              the orignators' input target areas, actual alert coverage depends on cellular
              system implementation and may vary."),
            p("For a map of currently active alerts, please visit ",
              a('warn.pbs.org', href='http://warn.pbs.org.'),
              "For more information about PBS WARN, please visit ",
              a('pbs.org/about/WARN', href='http://www.pbs.org/about/contact-information/warn/'),
              " or email ",
              a('George Molnar.', href='mailto://gjmolnar@pbs.org'),
              " Code available at ",
              a('Github.', href='https://github.com/amsilvr/warn_details')
            )
        ),
        dashboardBody(

            tags$style(type = "text/css", "#map {height: calc(100vh - 100px) !important;}"),

            
            #### choropleth map ####
            tabsetPanel(#type = "pills",
                        tabPanel("Interactive map", leafletOutput("map", width = "100%", height = "100%") %>%
                                     withSpinner(type = 6)),

                        #### list of alerts ####

                        tabPanel("List of events in selection",
                                 DT::dataTableOutput("events") %>%
                                     withSpinner(type = 6)
                        ) # tab
            ) # tabset
    )
)

server <-function(input, output) {

  observeEvent(input$showSidebar, {
        shinyjs::removeClass(selector = "body", class = "sidebar-collapse")
    })
    observeEvent(input$hideSidebar, {
        shinyjs::addClass(selector = "body", class = "sidebar-collapse")
    })

    output$type <- renderText(input$alertType)


    # Reactive variable fd containing (f)iltered (d)ata
    fd <- reactive({
    #  browser()
       alert_tally <- tally_alerts(msg2,
                                   fips_msg,
                                   start = input$dateRange[1],
                                   end = input$dateRange[2])
       
       qinst = rlang::sym(input$alertType)
       
       allCounties <- left_join(counties_sf, alert_tally)
       
       allCounties[is.na(allCounties)] <- 0
       allCounties <- allCounties %>% 
             select(GEOID,
                    NAME,
                    description,
                    STUSPS,
                    AMBER,
                    FlashFlood,
                    Hurricane,
                    Other,
                    Tornado,
                    Total,
                    geometry) %>% 
         mutate(inst = !!qinst)
       allCounties <- allCounties %>% 
             st_sf(sf_column_name = 'geometry')
       
       allCounties <- allCounties %>% 
             st_transform('+proj=longlat +datum=WGS84') %>% 
         
        return()

    })


    # Reactive variable containing click_data
    click_data <- reactiveValues(clickedMarker = NULL)

    # Default County Name
    output$county_name <- renderText("Full Country")
    output$events <- renderText("Please select a state and alert type.
                                Click on a county for a list of events in that county.")
    # Handle Dates in table and map
    observeEvent(input$dateRange,{
      # Most recent alert
        output$last_alert <- renderText(paste0(month(max(input$dateRange[2]),label = TRUE),' ',
                                               day(max(input$dateRange[2])),', ',
                                               year(max(input$dateRange[2]))))
    
      # First alert selected
        output$first_alert <- renderText(paste0(month(max(input$dateRange[1]),label = TRUE),' ',
                                               day(max(input$dateRange[1])),', ',
                                               year(max(input$dateRange[1]))))
        
        
})
    # Base Map ####
    output$map <- renderLeaflet({
        leaflet() %>%
            addProviderTiles(providers$Stamen.TonerLite) %>%
            setView(-98.5, 40,zoom = 4)
    })
    ## When you pick a full state, clear the clicked county
    observeEvent(input$state,{
        quostate <- quo(input$state)
        click_data$clickedShape$id <- NULL

        output$county_name <- renderText({
            input$state
        })

        if (input$state == "Full Country") {
            bounds <- list(-179.1505, 17.91377, -66.885444, 49.384358)
            leafletProxy('map') %>%
                removeShape(layerId = 'stateSelection') %>%
                fitBounds(lng1 = bounds[[1]],
                          lat1 = bounds[[2]],
                          lng2 = bounds[[3]],
                          lat2 = bounds[[4]])
        } else if(input$state == "Continental US") {
            bounds <- list(-124.848974, 24.396308, -66.885444, 49.384358)
            leafletProxy('map') %>%
                removeShape(layerId = 'stateSelection') %>%
                fitBounds(lng1 = bounds[[1]],
                          lat1 = bounds[[2]],
                          lng2 = bounds[[3]],
                          lat2 = bounds[[4]])
        } else if(input$state == "Alaska") { ##automatic bounds don't work here
            bounds <- list(-179.1505, 51.2097, -129.9795, 71.4410)
            brdr  <- state_sf %>%
                filter(NAME == 'Alaska') %>%
                st_sf()
            leafletProxy('map') %>%
                addPolygons(data = brdr,
                            layerId = 'stateSelection',
                            color = '#000',
                            weight = 3,
                            fill = FALSE) %>%
                fitBounds(lng1 = bounds[[1]],
                          lat1 = bounds[[2]],
                          lng2 = bounds[[3]],
                          lat2 = bounds[[4]]
                )
        } else {
            bounds <- state_sf %>% st_sf() %>%
                filter(NAME == !!quostate) %>%
                select(geometry) %>%
                st_bbox()
            brdr  <- state_sf %>%
                filter(NAME == !!quostate) %>%
                st_sf()
            leafletProxy('map') %>%
                addPolygons(data = brdr,
                            layerId = 'stateSelection',
                            color = '#000',
                            weight = 3,
                            fill = FALSE) %>%
                fitBounds(lng1 = bounds[[1]],
                          lat1 = bounds[[2]],
                          lng2 = bounds[[3]],
                          lat2 = bounds[[4]]
                )
        }
       # print(bounds)


    })
    # Alert Type ####

    observeEvent({
      input$alertType
      input$dateRange
      }, {
     # browser()
      at <- input$alertType
      ac <- fd()
      # print(ac)
 #       bins and pallette
      if (at == "Hurricane") {
        bins <- c(0,1,2,4,8,max(ac$inst))
      } else if (at == "Other") {
        bins <- c(0,1,2,4,8,16,32,64,max(ac$inst))
      } else bins <- c(unique(quantile(ac$inst,
                                       probs = seq(0,1,by = .12),
                                       type = 2)),max(ac$inst))
        pal <- colorBin("Blues",
                        domain = NULL,
                        bins = bins,
                        pretty = TRUE,
                        na.color = "#fefefe")
        
      #  browser()  

        leafletProxy('map') %>%
            clearShapes() %>%
            addPolygons(data = ac
                        , group = at
                        , layerId = ~GEOID
                        , stroke = FALSE
                        , label = ~paste0("<strong>"
                                          ,NAME
                                          ," "
                                          ,description #lookup table for lsad
                                          ,", "
                                          ,STUSPS
                                          ,":</strong><br />"
                                          ,inst
                                          ," "
                                          ,at
                                          ," WEA Messages") %>%
                            lapply(htmltools::HTML)
                        , labelOptions = labelOptions(style = list(
                            "color" = "#2b3e50",
                            "box-shadow" = "3px 3px rgba(0,0,0,0.25)",
                            "text-align" = "left",
                            "font-size" = "17px",
                            "border-color" = "rgba(0,0,0,0.5)"))
                         , fillOpacity = .6
                         , smoothFactor = .5
                         , fillColor = ~pal(inst)
                        , highlight = highlightOptions(
                           fillOpacity = .8,
                           bringToFront = TRUE)

            )
    })
    # Store the Map Boundaries on screen so map doesn't reset when new filters applied
    observeEvent(input$map1_bounds, {
        proxy <- leafletProxy("map") %>%
            setView(input$map1_bounds)
    })

    # Re-title the legend
    observeEvent({
      input$alertType
      input$dateRange
    }, {
      
      at <- input$alertType
      ac <- fd()
      
        #bins and pallette
        if (at == "Hurricane") {
            bins <- c(0,1,2,4,8,max(ac$inst))
        } else if (at == "Other") {
            bins <- c(0,1,2,4,8,16,32,64,max(ac$inst))
        } else bins <- c(unique(quantile(ac$inst,
                                         probs = seq(0,1,by = .12),
                                         type = 2)),max(ac$inst))
        pal <- colorBin("Blues",
                        domain = NULL,
                        bins = bins,
                        pretty = TRUE,
                        na.color = "#fefefe")
        proxy <- leafletProxy("map", data = ac) %>%
            clearControls() %>%
            addLegend(pal = pal
                      , values = ~inst
                      , opacity = .5
                      , title = paste0("Number of ",input$alertType," WEAs")
                      , position = "bottomleft"
                      , labFormat = labelFormat(digits = 0))
    })


    # store the clicked county
    observeEvent(input$map_shape_click, {
        click_data$clickedShape <- input$map_shape_click
    })
    # Get the county name for the clicked county
    observeEvent(input$map_shape_click, {
        loc_id = click_data$clickedShape$id
        output$county_name <- renderText({
            filter(fd(), GEOID == loc_id) %>%
                select(NAME, description, STUSPS) %>%
                st_set_geometry(NULL) %>%
                paste(collapse = " ")
        })
    })

    observeEvent(input$map_shape_click, {
        loc_id = click_data$clickedShape$id
        brdr = filter(fd(), GEOID == loc_id)
        leafletProxy('map') %>%
            addPolygons(data = brdr,
                        layerId = 'cty_sel',
                        color = '#000',
                        weight = 2,
                        fill = FALSE)
    })

    #Create a table with all the events of type in that geoid
    output$events <- renderDataTable({
        county_events = click_data$clickedShape$id
        quocounty = quo(county_events)
        state = input$state
        quostate = quo(state)
        alert_type = input$alertType
        # # debugging console messages
        # message(paste0('selected county is ',county_events))
        # message(paste0('selected state is ',state))
        # message(paste0('alert type is ',alert_type))
        # print(input$dateRange) ## 
        
        #### What are we looking to put in our table?
        #### Whole country or single county?
        if (is.null(county_events)) { ## All cases where we haven't selected a county
            if (state == 'Full Country') {
                tmptbl <- fips_msg
            } else if (state == 'Continental US') {
                tmptbl <- fips_msg %>%
                   # mutate(stfps = str_extract(GEOID, '^[0-9]{2}')) %>%
                    filter(!(stringr::str_extract(GEOID, '^[0-9]{2}') %in% c('02', '15', '72'))) #%>%
                  #  select(-stfps)
            } else{tmptbl <- fips_msg %>% ## Get all messages from given state
                mutate(stfps = str_extract(GEOID, '^[0-9]{2}')) %>%
                filter(stfps == state_sf %>%
                           st_set_geometry(NULL) %>% 
                           filter(NAME == !!quostate) %>%
                           select(STATEFP) %>%
                           as.character()) %>%
                select(-stfps)}
        } else {tmptbl <- fips_msg %>%
            filter(GEOID == !!quocounty)
        }
        #### All alerts or specific type?
        if (alert_type == 'Total') {
            tmptbl <- tmptbl %>%
                left_join(msg2)
        } else {
            tmptbl <- tmptbl %>%
                left_join(msg2) %>%
                filter(type == alert_type)}

        tmptbl <- tmptbl %>%
            distinct(msg_id,.keep_all = TRUE) %>%
            arrange(desc(rec_time)) %>%
            transmute(`Date` = rec_time
                      , `Message Text` = str_replace_all(wea, "\'", "")
                      , `Affected Areas` = areas) %>%
        ### Taking out date range inputs ###
            filter(Date >= input$dateRange[1]) %>%
            filter(Date <= input$dateRange[2])


        ###### Place Output into datatable ######
        datatable(tmptbl,
                  options = list(
                      initComplete = JS(
                          "function(settings, json) {",
                          "$(this.api().table().header()).css({'background-color': '#000', 'color': '#fff'});",
                          "}"),
                      columnDefs = list(list(
                          targets = 2,
                          render = JS(
                              "function(data, type, row, meta) {",
                              "return type === 'display' && data.length > 50 ?",
                              "'<span title=\"' + data + '\">' + data.substr(0, 50) + '...</span>' : data;",
                              "}")
                      )),
                      pageLength = 25,
                      lengthMenu = c(10, 25, 50, 100)),
                  class = 'stripe compact',
                  callback = JS('table.draw(false);'),
                  rownames = FALSE,
                  autoHideNavigation = TRUE,
                  selection = "single") %>%
            formatStyle(1:3, verticalAlign = 'top') %>%
            formatDate(1, 'toLocaleDateString')
    }
    )

}

shinyApp(ui, server)
