## CMAS Clean
#browser()
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

library(googlesheets)
library(tidyverse)
library(lubridate)
library(sf)
library(htmltab)

load_msgs <- function() {
    #browser()
    if (!dir.exists("data")) {dir.create("data")}
    source('_Monthly_Message_Copy.R')
        NewCMASImport()
     # get all records

       msg <-  all_cmas %>%
                mutate(rec_time = mdy_hms(gsub(" at ", " ", rec_time)
                                          , tz = "America/New_York"
                                          , truncated = 3)) %>%
                separate(full_text,
                         c("blank", "gateway_id" ,"msg_id"
                           ,"special_handling", "message_type"
                           , "category", "response_type", "severity"
                           , "urgency", "certainty", "expire_time"
                           , "text_language", "alert_message","dummy")
                         , sep = "CMAC_[:word:]*: "
                         , fill = "right" ## drops the warning for rows with too many records
                         , remove = TRUE
                )

        ## creates a table for fields with "update" records

        updates <- filter(msg, nchar(special_handling) < 10) %>%
                select(rec_time, cmac, gateway_id, msg_id
                       , ref_id = special_handling
                       , special_handling = message_type
                       , message_type = category
                       , category = response_type
                       , response_type = severity
                       , severity = urgency
                       , urgency = certainty
                       , certainty = expire_time
                       , text_language = alert_message
                       , alert_message = dummy
                )

        msg <- filter(msg, nchar(special_handling) >= 10) %>%
                select(-blank, -dummy)

        ## puts all the records back into a single table and
        ## uses two different separators to split out the alert
        ## text from the plain English "area" field
        ## and finally removes the tcs boilerplate

        msg <- bind_rows(msg, updates) %>%
                mutate(expire_time = ymd_hms(expire_time)) %>%
                separate(alert_message, c("message_text","t2")
                         , sep = "Targeted Areas: "
                         , remove = TRUE) %>%
                separate(t2, c("areas"), sep = "[:punct:]{4}"
                         , extra = "drop", remove = TRUE) %>%
                mutate(threat_type = gsub("\\. .*","", cmac)
                        , msg_id = as.character(str_trim(msg_id))
                        , areas = str_trim(areas)) %>%
                dplyr::filter(!(gateway_id == "http://tcs.tsis.com\n") )

       msg <- msg[-grep(" test", msg$threat_type),]

       return(msg)

    }
# State and Territory Lookup

map_states <- function() {
    state_url <- "https://www2.census.gov/geo/tiger/GENZ2016/shp/cb_2016_us_state_20m.zip"

    if (!dir.exists("data")) {dir.create("data")}
    if (!file.exists("data/state_shape_file.zip")) {
        download.file(state_url,
                      destfile = "data/state_shape_file.zip",
                      method = "libcurl")
        }
    t <- unzip("data/state_shape_file.zip", exdir = "data")
    # Read the file with sf
    state_sf <- st_read(t[grep("shp$",t)], stringsAsFactors = FALSE) %>%
        #as_tibble() %>%
        select(STATEFP, STUSPS, NAME, geometry) %>% 
        st_transform('+proj=longlat +datum=WGS84')
    

    file.remove(t)

    return(state_sf)
}


map_counties <- function() {
  #browser()
  # Download Shapefiles
    countyshapes_url <- "https://www2.census.gov/geo/tiger/GENZ2016/shp/cb_2016_us_county_20m.zip"
    if (!dir.exists("data")) {dir.create("data")}
    if (!file.exists("data/county_shape_file.zip")) {
        download.file(countyshapes_url, 
                      destfile = "data/county_shape_file.zip",
                      method = "libcurl")
    }

    c_shp <- unzip(zipfile = 'data/county_shape_file.zip',
                   exdir = 'data')

    counties_sf <- st_read(c_shp[grep("shp$", c_shp)], stringsAsFactors = FALSE) %>%
        as_tibble() %>% #to fix July 25 problem with the join.sf methods
        inner_join(as.data.frame(lsad_lookup())) %>%
        select(STATEFP,
               COUNTYFP,
               GEOID,
               NAME,
               description,
               geometry) %>%
        left_join(state_sf %>% 
                    select(STATEFP, STUSPS) %>% 
                    st_set_geometry(NULL), 
                  by = "STATEFP") %>%
        mutate(GEOID = as.ordered(GEOID))  %>% 
        st_sf(sf_column_name = 'geometry')  %>%
        st_transform('+proj=longlat +datum=WGS84')

    file.remove(c_shp)

    return(counties_sf)
    }


## Download local copy of FIPS lookup data and read into memory
load_fips <- function() {
      counties_sf <- map_counties() %>%
        as.data.frame() %>%
        transmute(areaname = paste(STUSPS, NAME),
               GEOID = as.character(GEOID)) %>%
          as.tibble() # %>%
}

# This looks up the location classification names from lsad.html
# and makes them readable for the data labels in the choropleth

lsad_lookup <- function() {
  url <- "https://www.census.gov/geo/reference/lsad.html"
  lsad <- htmltab::htmltab(doc = url, which = "//th[text() = 'LSAD']/ancestor::table") %>%
    filter(grepl("06|04|12|05|03|00|15|25|13", LSAD) == TRUE) %>%
    transmute(LSAD,description = `LSAD Description`) %>%
    mutate(description =
                str_extract(pattern = "^[^(]*",string = description) %>%
                str_trim() %>%
                str_to_title()) %>%
    replace_na(list(LSAD = "", description = "")) %>%
    filter(!description == "Balance Of County Ec Place")

}

## Returns a location in the form "ST, County" from the supplied County (ST) format

area_find <- function(area_list) {
        area_list <- str_replace_all(area_list
                     , pattern = "(([A-z]*) \\(([A-Z]{2})\\)), \\1"
                     , replacement = "\\2 city \\(\\3\\), \\2 \\(\\3\\)"
                     )

        m <- str_match_all(string = area_list
                             , pattern = "[A-z. ]{3,} ")

        n <- str_match_all(string = area_list
                           , pattern = "\\(?([A-Z]{2})\\)?")

        area_clean <- paste(n[[1]][,2]
                            , str_trim(m[[1]][,1], side = "both")) %>%

  # ## Clean supplied county names to match list from census county map
  # ##
        str_replace_all(pattern = "E\\.",replacement = "East") %>%
        str_replace_all(pattern = "W\\.",replacement = "West") %>%
        str_replace_all(pattern = "(IN La|IL La) (Porte|Salle)",replacement = "\\1\\2") %>%
        str_replace_all(pattern = "FL Dade", "FL Miami-Dade") %>%
        str_replace_all(pattern = "PR lsabela", "PR Isabela") %>%
        str_replace_all(pattern = "TX wall", "TX Wall") %>%
        str_replace_all(pattern = "TX hell", "TX Hall") %>%
        str_replace_all(pattern = "MT Lewis Clark", "MT Lewis and Clark") %>%
        str_replace_all(pattern = "SD Shannon", "SD Oglala Lakota") # Name Change effective 5/1/2015
       return(area_clean)

}

## Substitutes all counties in a state
## For areas that include only state names

full_state <- function(areas_states) {
  if (!exists("fips_lookup")) fips_lookup <- load_fips() 
  
  fips_lookup %>%
        mutate(STUSPS = str_match(areaname, "[A-Z]{2}")) %>%
        distinct() %>%
        right_join(areas_states) %>%
        transmute(msg_id = as.character(msg_id)
                  ,GEOID = as.character(GEOID)) %>%
        return()
}

flatten_fips <- function(msg) {
 # browser()
  if (!exists("fips_lookup")) fips_lookup <- load_fips()
  areas <- msg %>% 
           select(msg_id, areas)
  #separate out alerts with full state areas, convert directly to fips
  areas_states <- areas %>% 
      filter(str_length(areas) == 2) %>%
      select(msg_id, STUSPS = areas) %>%
      full_state()
  #remove those alerts from the other areas
  areas <- filter(areas, str_length(areas) > 2) %>% 

  # create a matrix of areas for each message id that has individual counties
            transmute(msg_id = msg_id,
                  areaname = map(areas, area_find)) %>% 
            unnest() %>% 
            left_join(fips_lookup) %>%
            transmute(msg_id, areaname, GEOID)  

  # Fix the 18 that don't seem to match for whatever reason
          areas <- areas %>%   
  
          mutate(msg_id, GEOID =
             case_when(
                      grepl("MD Baltimore city"
                            ,areas$areaname, ignore.case = TRUE) ~ "24005",
                      grepl("SD Shannon",areas$areaname) ~ "46113",
                      grepl("TX Wall",areas$areaname) ~ "48473",
                      grepl("NV Carson",areas$areaname) ~ "32510",
                      grepl("PR Rio Grande",areas$areaname) ~ "72119",
                      grepl("PR Manati",areas$areaname) ~ "72091",
                      grepl("PR Juana Diaz",areas$areaname) ~ "72075",
                      grepl("PR Loiza",areas$areaname) ~ "72087",
                      grepl("LA La Salle",areas$areaname) ~ "22059",
                      grepl("SD Pennington city",areas$areaname) ~ "46103",
                      grepl("PR Las Marias",areas$areaname) ~ "72083",
                      grepl("CA Lake city",areas$areaname) ~ "06033",
                      grepl("PR Comerio",areas$areaname) ~ "72045",
                      grepl("KY Carter city",areas$areaname) ~ "21043",
                      grepl("VA Roanoke city",areas$areaname) ~ "51770",
                      grepl("MN McLeod city",areas$areaname) ~ "27085",
                      grepl("AK Wrangell-Petersburg", areas$areaname) ~ "02275",
                      grepl("AK Prince of", areas$areaname) ~ "02198",
                      grepl("AK Cordova", areas$areaname) ~ "02261",
                      grepl("AK Koyukuk", areas$areaname) ~ "02290",
                      grepl("AK Outer Ketchikan", areas$areaname) ~ "02130",
                      grepl("AK Susitna", areas$areaname) ~ "02170",
                      grepl("AZ Cochise city", areas$areaname) ~ "04003",
                      grepl("AZ Pima city", areas$areaname) ~ "04019",
                      grepl("IN Lagrange", areas$areaname) ~ "18087",
                      grepl("MO vingston", areas$areaname) ~ "29117",
                      grepl("WY Campbell city", areas$areaname) ~ "56005",
                      grepl("CO Park", areas$areaname) ~ "08093",
                      grepl("MO rid", areas$areaname) ~ "29143",
                      grepl("AR Buren", areas$areaname) ~ "05141",

                      ## Account for accents in county names ##
                     
                      grepl("NM Dona Ana", areas$areaname) ~ "35013", ## Account for ñ
                      grepl("PR Anasco", areas$areaname) ~ "72011", ## Account for ñ
                      grepl("PR Catano", areas$areaname) ~ "72033", ## Account for ñ
                      grepl("PR Penuelas", areas$areaname) ~ "72111", ## Account for ñ
                      grepl("PR Bayamon", areas$areaname) ~ "72021", ## Account for ó
                      grepl("PR Canovanas", areas$areaname) ~ "72029", ## Account for ó
                      grepl("PR Guanica", areas$areaname) ~ "72055", ## Account for á
                      grepl("PR Mayaguez", areas$areaname) ~ "72097", ## Account for ü
                      grepl("PR Rincon", areas$areaname) ~ "72117", ## Account for ó
                      grepl("PR San German", areas$areaname) ~ "72125", ## Account for á
                      grepl("PR San Sebastian", areas$areaname) ~ "72131", ## Account for á

                      TRUE ~ areas$GEOID
                )
      )    %>%
    # Get rid of accidental duplicates
            filter(!areaname == "MO New") %>% 
            filter(!areaname == "AR Van") %>% 
    select(-areaname) %>%
    rbind(areas_states) %>%
    #mutate(GEOID = as.ordered(GEOID)) %>% 
    return()
}

# Classify message type - as
# Tornado, Flash Flood, AMBER, Hurricane, or Other

classify_message <- function(msg) {

  mutate(msg, type =
           case_when(
             grepl("Tornado", msg$message_text, ignore.case = TRUE) ~ "Tornado",
             grepl("Flash Flood", msg$message_text, ignore.case = TRUE) ~ "FlashFlood",
             grepl("Amber", msg$message_text, ignore.case = TRUE) ~ "AMBER",
             grepl("Kidnap", msg$message_text, ignore.case = TRUE) ~ "AMBER",
             grepl("child", msg$message_text, ignore.case = TRUE) ~ "AMBER",
             grepl("Hurricane", msg$message_text, ignore.case = TRUE) ~ "Hurricane",
             #grepl("Tsunami", msg$message_text, ignore.case = TRUE) ~ "Tsunami",
             TRUE ~ "Other")
  ) %>%
    transmute(msg_id = as.character(msg_id), rec_time
              , expire_time
              , response = response_type
              , urgency
              , wea = message_text
              , type = as.factor(type)
              , areas
    )
}

tally_alerts <- function(df = msg2, fipsMsg = fips_msg,
                        start = NULL,
                        end = NULL 
                        ) {
  #  browser()
  #  if(is.null(start)) start = min(df$rec_time)
  #  if(is.null(end)) end = max(df$rec_time)
    t <- df %>%
        #filter(rec_time >= start) %>%
        #filter(rec_time <= end) %>%
        left_join(fipsMsg) %>%
        select(msg_id, GEOID, type) %>%
        #mutate(GEOID = factor(GEOID, levels = levels(counties_sf$GEOID))) %>% 
        group_by(GEOID, type) %>%
        tally() %>%
        rename(WEATYPE = type, WEANUM = n) %>%
        spread(WEATYPE, WEANUM, fill = "0",drop = TRUE, convert = TRUE) %>%
        mutate(Total = AMBER + FlashFlood
               + Hurricane + Other + Tornado)
       
 #   t[is.na(t)] <- 0
    
    return(t)
    
    }

######################
## Run Functions  ####
# Either load all messages from the google sheet or load the full environment from the wea_alerts.rda file.

load_vars <- function() { ## Loads variables into global environment
    #browser()
    state_sf <<- map_states()
    counties_sf <<- map_counties()

    msg2 <<- load_msgs() %>%
        classify_message()

    fips_msg <<- flatten_fips(msg2)

    alert_tally <<- tally_alerts(msg2, fips_msg)
    
}


