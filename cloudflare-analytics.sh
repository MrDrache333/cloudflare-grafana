#!/bin/bash
##      .SYNOPSIS
##      Grafana Dashboard for Cloudflare - Using RestAPI to InfluxDB Script
## 
##      .DESCRIPTION
##      This Script will query Cloudflare GraphQL and send the data directly to InfluxDB, which can be used to present it to Grafana. 
##      The Script and the Grafana Dashboard it is provided as it is, and bear in mind you can not open support Tickets regarding this project. It is a Community Project
##
##      .Notes
##      NAME:  cloudflare-analytics.sh
##      LASTEDIT: 01-2025
##      VERSION: 2.1
##      KEYWORDS: Cloudflare, InfluxDB, Grafana

# Endpoint URL for InfluxDB
InfluxDBURL="${InfluxDBURL:-http://influxdb}" # Default fallback
InfluxDBPort="${InfluxDBPort:-8086}"
InfluxDB="${InfluxDB:-telegraf}"
InfluxDBUser="${InfluxDBUser:-telegraf}"
InfluxDBPassword="${InfluxDBPassword:-telegraf}"

# Endpoint URL for login action
cloudflareauthmethod="${AUTH_METHOD:-TOKEN}" # Auth method 'TOKEN' or 'APIKEY'
cloudflareapikey="${AUTH_APIKEY:-YOURAPIKEY}" # When using APIKEY as authmethod, provide the apikey
cloudflareemail="${AUTH_MAIL:-YOUREMAIL}" # When using APIKEY as authmethod, provide the auth email
cloudflareapitoken="${AUTH_TOKEN:-YOURAUTHTOKEN}" # When using TOKEN as authmethod, provide the auth TOKEN
cloudflarezone="${ZONE_ID:-YOURZONEID}"


# Time variables
back_seconds="${QUERY_TIME:-3600*24}"
end_epoch=$(date +'%s')
let start_epoch=$end_epoch-$back_seconds
start_date=$(date --date="@$start_epoch" +'%Y-%m-%d')
end_date=$(date --date="@$end_epoch" +'%Y-%m-%d')

# Payload to query to the new GraphQL (You can always add more variables, or remove the ones you do not need)
PAYLOAD='{ "query":
  "query {
  viewer {
    zones(filter: {zoneTag: $zoneTag}) {
      httpRequests1dGroups(limit:7, filter: $filter,)   {
        dimensions {
          date
        }
        sum {
          browserMap {
            pageViews
            uaBrowserFamily
          }
          bytes
          cachedBytes
          cachedRequests
          contentTypeMap {
            bytes
            requests
            edgeResponseContentTypeName
          }
          countryMap {
            bytes
            requests
            threats
            clientCountryName
          }
          encryptedBytes
          encryptedRequests
          ipClassMap {
            requests
            ipType
          }
          pageViews
          requests
          responseStatusMap {
            requests
            edgeResponseStatus
          }
          threats
          threatPathingMap {
            requests
            threatPathingName
          }
        }
        uniq {
          uniques
        }
      }
    }
  }
}",'
PAYLOAD="$PAYLOAD

  \"variables\": {
    \"zoneTag\": \"$cloudflarezone\",
    \"filter\": {
      \"date_geq\": \"$start_date\",
      \"date_leq\": \"$end_date\"
    }
  }
}"

##
# Cloudflare Analytics. This part will check on your Cloudflare Analytics, extracting the data from the last 24 hours
##
## URL with API email and key
echo "Auth-method: $cloudflareauthmethod"
echo "Auth-Token: $cloudflareapitoken"
case $cloudflareauthmethod in
        APIKEY)
cloudflareUrl=$(curl -s -X POST -H "Content-Type: application/json" -H "X-Auth-Email: $cloudflareemail" -H  "X-Auth-Key: $cloudflareapikey" --data "$(echo $PAYLOAD)" https://api.cloudflare.com/client/v4/graphql/ 2>&1 -k --silent)
;;
## URL with API Token
        TOKEN)
cloudflareUrl=$(curl -s -X POST -H "Content-Type: application/json" -H "Authorization: Bearer $cloudflareapitoken" --data "$(echo $PAYLOAD)" https://api.cloudflare.com/client/v4/graphql/ 2>&1 -k --silent)
;;
        *)
        echo "No or Wrong Input in Config for 'cloudflareauthmethod'. Current value is $cloudflareauthmethod"
;;
esac

echo "Endpoint: $cloudflareUrl"
    declare -i arraydays=0
    for requests in $(echo "$cloudflareUrl" | jq -r '.data.viewer.zones[0].httpRequests1dGroups[].sum.requests'); do
        ## Requests
        cfRequestsAll=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.requests")
        if [[ $cfRequestsAll = "null" ]]; then
            break
        else
        cfRequestsCached=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.cachedRequests")
        cfRequestsUncached=$(echo "$cfRequestsAll - $cfRequestsCached" | bc)
        
        ## Bandwidth
        cfBandwidthAll=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.bytes")
        cfBandwidthCached=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.cachedBytes")
        cfBandwidthUncached=$(echo "$cfBandwidthAll - $cfBandwidthCached" | bc)

        ## Threats
        cfThreatsAll=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.threats")

        ## Pageviews
        cfPageviewsAll=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.pageViews")

        ## Unique visits
        cfUniquesAll=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].uniq.uniques")

        ## Timestamp
        date=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].dimensions.date")
        cfTimeStamp=`date -d "${date}" '+%s'`


        #echo "cloudflare_analytics,cfZone=$cloudflarezone cfRequestsAll=$cfRequestsAll,cfRequestsCached=$cfRequestsCached,cfRequestsUncached=$cfRequestsUncached,cfBandwidthAll=$cfBandwidthAll,cfBandwidthCached=$cfBandwidthCached,cfBandwidthUncached=$cfBandwidthUncached,cfThreatsAll=$cfThreatsAll,cfPageviewsAll=$cfPageviewsAll,cfUniquesAll=$cfUniquesAll $cfTimeStamp"

        echo "Writing Zone data to InfluxDB cloudflare_analytics"
        curl -i -XPOST "$InfluxDBURL:$InfluxDBPort/write?precision=s&db=$InfluxDB" -u "$InfluxDBUser:$InfluxDBPassword" --data-binary "cloudflare_analytics,cfZone=$cloudflarezone cfRequestsAll=$cfRequestsAll,cfRequestsCached=$cfRequestsCached,cfRequestsUncached=$cfRequestsUncached,cfBandwidthAll=$cfBandwidthAll,cfBandwidthCached=$cfBandwidthCached,cfBandwidthUncached=$cfBandwidthUncached,cfThreatsAll=$cfThreatsAll,cfPageviewsAll=$cfPageviewsAll,cfUniquesAll=$cfUniquesAll $cfTimeStamp"

        ## Requests per Country
        declare -i arraycountry=0
        for requests in $(echo "$cloudflareUrl" | jq -r '.data.viewer.zones[0].httpRequests1dGroups[].sum.countryMap[]'); do
            cfRequestsCC=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.countryMap[$arraycountry].clientCountryName")
            if [[ $cfRequestsCC = "null" ]]; then
                break
            else
            cfRequests=$(echo "$cloudflareUrl" | jq --raw-output ".data.viewer.zones[0].httpRequests1dGroups[$arraydays].sum.countryMap[$arraycountry].requests // "0"")

            echo "Writing stats for day $date"
            #echo "cloudflare_analytics_country,country=$cfRequestsCC visits=$cfRequests $cfTimeStamp"

            echo "Writing Zone data per Country to InfluxDB cloudflare_analytics_country to endpoint $InfluxDBURL:$InfluxDBPort/write?precision=s&db=$InfluxDB"
            curl -i "$InfluxDBURL:$InfluxDBPort/write?precision=s&db=$InfluxDB" -u "$InfluxDBUser:$InfluxDBPassword" --data-binary "cloudflare_analytics_country,country=$cfRequestsCC visits=$cfRequests $cfTimeStamp"

            arraycountry=$arraycountry+1
            fi
        done          
        
        arraydays=$arraydays+1
        fi
    done  
sleep $back_seconds
