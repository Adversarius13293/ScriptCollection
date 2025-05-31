param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "YourUserName",
    [Parameter(Mandatory = $false)]
    [switch]$Fine = $false,
    [Parameter(Mandatory = $false)]
    [switch]$Undercut = $true,
    [Parameter(Mandatory = $false)]
    [switch]$Overpriced = $false,
    [Parameter(Mandatory = $false)]
    [switch]$Priceorder = $true,
    [Parameter(Mandatory = $false)]
    [switch]$WriteOutput = $false
)
# https://warframe.market/
# Goals:
## Find orders of same price that are in front of me. To then refresh my order.
## Find orders with at least 3 other orders that are cheaper. To maybe lower my price.
## Find orders where I have the cheapest price, and the next orders are more expensive. To maybe increase my price.

# Convert username to lowercase for the slug
$userSlug = $Username.ToLower()
$baseUrl = "https://api.warframe.market/v2"

function Log {
    param (
        [string]$Message
    )
    if($WriteOutput) {
        Write-Output("[$((Get-Date).ToString('dd.MM. HH:mm:ss'))]: $Message")
    }
}
function Invoke-Api {
    param (
        [string]$url
    )
    try {
        Log("Doing API request, slowing down: $url")
        Start-Sleep -Milliseconds 500
        return Invoke-RestMethod -Uri $url -Method Get -Headers @{
            Accept = "application/json"
            Platform = "pc"
            Language = "en"
        }
    } catch {
        Write-Warning "API call failed: $url"
        return $null
    }
}
Write-Output("$((Get-Date).ToString('HH:mm:ss')) Start getting data...")
# Step 0: Get ALL items, to translate item id into item slug.
$script:itemList = Invoke-Api "$baseUrl/items"
function Get-Item-Slug {
    param (
        [string]$itemId
    )
    return $script:itemList.data | Where-Object { $_.id -eq $itemId } | Select-Object -ExpandProperty slug
}

# Step 1: Get all sell orders of the user
$userOrdersData = Invoke-Api "$baseUrl/orders/user/$userSlug"
Log("Order Data: $userOrdersData")
$userSellOrders = $userOrdersData.data | Where-Object { $_.type -eq "sell" }
Log("Sell Orders: $($userSellOrders.Count)")

foreach ($order in $userSellOrders) {
    $isFine = $true
    $itemSlug = Get-Item-Slug($order.itemId)
    Log("Got item slug: $itemSlug")
    $userPrice = $order.platinum
    Log("User price: $userPrice")

	if($itemSlug -eq "warhead") {
##		Personal breakpoint entry for easier debugging.
		Log("At breakpoint for $itemSlug")
	}

    # Step 2: Get top sell orders for the item
    $topOrdersData = Invoke-Api "$baseUrl/orders/item/$itemSlug/top"
    if (-not $topOrdersData) {
        Write-Output("Found no orders for $itemSlug.")
        continue
    }

    $topSellOrders = $topOrdersData.data.sell

    # Check how many same-price orders are ahead
    # The user orders are sometimes not updated quickly enough. So also check for the username.
    # TODO: That only fixed the comparison against my own orders. It still has the old date from my orders, and compares it to the current offers.
    $samePriceMoreRecentCount = (@($topSellOrders | Where-Object { $_.platinum -eq $userPrice -and $_.updatedAt -gt $order.updatedAt -and $_.user.slug -ne $userSlug })).Count
    if ($samePriceMoreRecentCount -gt 0) {
        if($Priceorder) {
            Write-Output "User's sell order is behind $samePriceMoreRecentCount same-price offer(s) of $($userPrice) platinum: [$itemSlug]"
        }
        $isFine = $false
    }

    # Count how many orders are cheaper
    $cheaperCount = 0
    $cheaperCount = (@($topSellOrders | Where-Object { $_.platinum -lt $userPrice })).Count
    if ($cheaperCount -ge 3) {
        if($Overpriced) {
            Write-Output "There are at least 3 cheaper sell orders than the user's price of $($userPrice): [$itemSlug]"
        }
        $isFine = $false
    }

    # Check if the cheapest offer is at least 1 platinum higher than user's
    if($topSellOrders[0].user.slug -eq $userSlug) {
        $lowestPrice = $topSellOrders[1].platinum
    } else {
        # If user is not online.
        $lowestPrice = $topSellOrders[0].platinum
    }
    if ($lowestPrice -gt ($userPrice + 1)) {
        if($Undercut) {
            Write-Output "User's price of $userPrice is undercutting the market, which is currently $($lowestPrice): [$itemSlug]"
        }
        $isFine = $false
    }
    if($isFine -and $Fine) {
        Write-Output "Item is fine with the price of $($userPrice): [$itemSlug]"
    }
}
Write-Output "$((Get-Date).ToString('HH:mm:ss')) Program done."
