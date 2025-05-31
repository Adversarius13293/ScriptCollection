# 20250331 Script to check the weather within the next day and the next 3 days.
# Example batch script to start this powershell script regardless of ExecutionPolicy. Can be put into autostart.
#@echo off
#powershell -ExecutionPolicy Bypass -File "C:\path\to\your\check_weather.ps1"

# TODO: Seems to pick a city a bit too far away from the given coordinates?
# And, maybe because of that, the data seems to differ compared to other weather data.

# Set OpenWeatherMap API key
$apiKey = "GetYourOwnKey"
# Location
$lat = "11.222"
$lon = "22.333"

# Define the hour of the next day for the first forecast. For example "20" for the timespan until the next day at 20:00 o'clock.
$forecastHoursTime = 20
# Define the second forecast period in days
$forecastPeriodDays = 3

# Free OpenWeatherMap API URL for the 5-day forecast in 3-hour segments
# Every 3 hours, starting at 0 UTC. Most likely weather data of the last 3 hours of each timestamp.
$url = "https://api.openweathermap.org/data/2.5/forecast?lat=$lat&lon=$lon&units=metric&appid=$apiKey"

# Toggle Logging
$writeOutput = $true

#### End of configuration

Function log {
    param (
        [string]$Message
    )
    if($writeOutput) {
        Write-Host("[$((Get-Date).ToString('dd.MM. HH:mm:ss'))]: $Message")
    }
}

Function FormatNumber {
    param (
        [Parameter(Mandatory = $true)]
        [double]$number
    )

    # If the number is an integer, return it without decimals, otherwise return up to 2 decimal points
    if ($number -eq [math]::Floor($number)) {
        return $number.ToString("0")
    } else {
        return $number.ToString("0.00")
    }
}

# Initialize variables to store accumulated values for "next time"
$humidityTotalNextTime = 0.
$popTotalNextTime = 0.
$rainTotalNextTime = 0.
$humidityMaxNextTime = 0.
$popMaxNextTime = 0.
$rainMaxNextTime = 0.
$forecastCountNextTime = 0

# Initialize variables for the forecast period (next X days)
$humidityTotalForecastPeriod = 0.
$popTotalForecastPeriod = 0.
$rainTotalForecastPeriod = 0.
$humidityMaxForecastPeriod = 0.
$popMaxForecastPeriod = 0.
$rainMaxForecastPeriod = 0.
$forecastCountForecastPeriod = 0

$currentTime = Get-Date
# Always set to the next day.
$NextTimeTime = $currentTime.AddDays(1).Date.AddHours($forecastHoursTime)
# Calculate the next time we reach the specified hour of a day
#$NextTimeTime = if ($currentTime.Hour -lt $forecastHoursTime) {
#    # If it's before the time today, it will be later today
#    $currentTime.Date.AddHours($forecastHoursTime)
#} else {
#    # If it's after the time, it will be tomorrow
#    $currentTime.AddDays(1).Date.AddHours($forecastHoursTime)
#}
log("Current time: $currentTime, computed NextTime: $NextTimeTime.")

# Send a request to get the weather data
$response = Invoke-RestMethod -Uri $url -Method Get

# Check the weather data up to the next time, and for the configured forecast period
foreach ($forecast in $response.list) {
    # dt: "Time of data forecasted, unix, UTC"
    $forecastTime = (Get-Date "01.01.1970").AddSeconds($forecast.dt).ToLocalTime()
    log("Extracted forecast time: $forecastTime")

    # Evaluate for up to the next defined time of the day
    if ($forecastTime -gt $currentTime -and $forecastTime -le $NextTimeTime) {
        $humidityTotalNextTime += $forecast.main.humidity
        $popTotalNextTime += $forecast.pop*100
        if ($forecast.rain.'3h' -ne $null) {
            $rainTotalNextTime += $forecast.rain.'3h'
        }

        $humidityMaxNextTime = [Math]::Max($humidityMaxNextTime, $forecast.main.humidity)
        $popMaxNextTime = [Math]::Max($popMaxNextTime, $forecast.pop*100)
        if ($forecast.rain.'3h' -ne $null) {
            $rainMaxNextTime = [Math]::Max($rainMaxNextTime, $forecast.rain.'3h')
        }

        $forecastCountNextTime++
    }

    # Evaluate for the next X days
    if ($forecastTime -gt $currentTime -and $forecastTime -lt $currentTime.AddDays($forecastPeriodDays)) {
        $humidityTotalForecastPeriod += $forecast.main.humidity
        $popTotalForecastPeriod += $forecast.pop*100
        if ($forecast.rain.'3h' -ne $null) {
            $rainTotalForecastPeriod += $forecast.rain.'3h'
        }
        $humidityMaxForecastPeriod = [Math]::Max($humidityMaxForecastPeriod, $forecast.main.humidity)
        $popMaxForecastPeriod = [Math]::Max($popMaxForecastPeriod, $forecast.pop*100)
        log("Rain chance $($forecast.pop*100)")
        if ($forecast.rain.'3h' -ne $null) {
            log("Rain amount $($forecast.rain.'3h')")
            $rainMaxForecastPeriod = [Math]::Max($rainMaxForecastPeriod, $forecast.rain.'3h')
        }

        $forecastCountForecastPeriod++
    }
}

# Calculate averages
$humidityAvgNextTime = if ($forecastCountNextTime -gt 0) { $humidityTotalNextTime / $forecastCountNextTime } else { -1 }
$popAvgNextTime = if ($forecastCountNextTime -gt 0) { $popTotalNextTime / $forecastCountNextTime } else { -1 }
$rainAvgNextTime = if ($forecastCountNextTime -gt 0) { $rainTotalNextTime / $forecastCountNextTime } else { -1 }

$humidityAvgForecastPeriod = if ($forecastCountForecastPeriod -gt 0) { $humidityTotalForecastPeriod / $forecastCountForecastPeriod } else { -1 }
$popAvgForecastPeriod = if ($forecastCountForecastPeriod -gt 0) { $popTotalForecastPeriod / $forecastCountForecastPeriod } else { -1 }
$rainAvgForecastPeriod = if ($forecastCountForecastPeriod -gt 0) { $rainTotalForecastPeriod / $forecastCountForecastPeriod } else { -1 }

log("Till next $($NextTimeTime.ToString('HH:mm')) Average: $(FormatNumber($humidityAvgNextTime))% humidity, $(FormatNumber($popAvgNextTime))% rain chance, $(FormatNumber($rainAvgNextTime))mm rain")
log("Till next $($NextTimeTime.ToString('HH:mm')) Maximum: $(FormatNumber($humidityMaxNextTime))% humidity, $(FormatNumber($popMaxNextTime))% rain chance, $(FormatNumber($rainMaxNextTime))mm rain")
log("Till next $($NextTimeTime.ToString('HH:mm')) Evaluated data points: $forecastCountNextTime")

log("Next $forecastPeriodDays days Average: $(FormatNumber($humidityAvgForecastPeriod))% humidity, $(FormatNumber($popAvgForecastPeriod))% rain chance, $(FormatNumber($rainAvgForecastPeriod))mm rain")
log("Next $forecastPeriodDays days Maximum: $(FormatNumber($humidityMaxForecastPeriod))% humidity, $(FormatNumber($popMaxForecastPeriod))% rain chance, $(FormatNumber($rainMaxForecastPeriod))mm rain")
log("Next $forecastPeriodDays days Evaluated data points: $forecastCountForecastPeriod")

# if bad weather till next time, then alert
# if good weather over the next x days, then alert
# what exactly is good/bad weather?

# TODO: What about snow? combine rain with list.snow.3h ?

# Display message based on the calculated averages and maximums
Add-Type -AssemblyName System.Windows.Forms
if ($rainMaxForecastPeriod -eq 0 -and $popMaxForecastPeriod -eq 0) {
    [System.Windows.Forms.MessageBox]::Show("No rain within the next $forecastPeriodDays days! `nAverage $(FormatNumber($humidityAvgForecastPeriod))% and maximum $(FormatNumber($humidityMaxForecastPeriod))% humidity", "Weather Notification")
} elseif ($rainMaxNextTime -ge 0.2 -or $popMaxNextTime -ge 15) {
    [System.Windows.Forms.MessageBox]::Show("It will probably rain soon. `nAverage $(FormatNumber($popAvgNextTime))% and maximum $(FormatNumber($popMaxNextTime))% chance, average $(FormatNumber($rainAvgNextTime))mm and maximum $(FormatNumber($rainMaxNextTime))mm rain, average $(FormatNumber($humidityAvgNextTime))% and maximum $(FormatNumber($humidityMaxNextTime))% humidity.", "Weather Notification")
} else {
    [System.Windows.Forms.MessageBox]::Show("Not good, not bad. `nTill tomorrow: Average $(FormatNumber($popAvgNextTime))% and maximum $(FormatNumber($popMaxNextTime))% chance, average $(FormatNumber($rainAvgNextTime))mm and maximum $(FormatNumber($rainMaxNextTime))mm rain, average $(FormatNumber($humidityAvgNextTime))% and maximum $(FormatNumber($humidityMaxNextTime))% humidity.
Till next $forecastPeriodDays days: Average $(FormatNumber($popAvgForecastPeriod))% and maximum $(FormatNumber($popMaxForecastPeriod))% chance, average $(FormatNumber($rainAvgForecastPeriod))mm and maximum $(FormatNumber($rainMaxForecastPeriod))mm rain, average $(FormatNumber($humidityAvgForecastPeriod))% and maximum $(FormatNumber($humidityMaxForecastPeriod))% humidity.", "Weather Notification")
}
