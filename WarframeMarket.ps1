param (
    [Parameter(Mandatory = $false)]
    [string]$Username = "YourUserName",
    [Parameter(Mandatory = $false)]
    [switch]$Fine = $false,         # Show a message for items with no found problems.
    [Parameter(Mandatory = $false)]
    [switch]$Undercut = $true,      # Show items which undercut the current market by more than 1 plat.
    [Parameter(Mandatory = $false)]
    [switch]$Priceorder = $true,    # Show items where other orders with the same price are in front of the user.
    [Parameter(Mandatory = $false)]
    [switch]$Overpriced = $false,   # Show items with too many other cheaper orders.
    [Parameter(Mandatory = $false)]
    [int]$OverpricedCount = 5,      # How many cheaper orders are fine for the Overpriced option.
    [Parameter(Mandatory = $false)]
    [int]$CheckBuy = $true,         # Whether or not to also check buy orders.
    [Parameter(Mandatory = $false)]
    [int]$TopSyndicateMods = 3      # How many of the most profitable mods per syndicate should be printed. 0 to disable.
)
# https://warframe.market/
# Goals:
## Find orders of same price that are in front of me. To then refresh my order.
## Find orders with at least X other orders that are cheaper. To maybe lower my price.
## Find orders where I have the cheapest price, and the next orders are more expensive. To maybe increase my price.
## Find best Syndicate mods to sell.

# Convert username to lowercase for the slug
$userSlug = $Username.ToLower()
$baseUrl = "https://api.warframe.market/v2"

function Log {
    param (
        [string]$Message
    )
    Write-Verbose("[$((Get-Date).ToString('dd.MM. HH:mm:ss'))]: $Message")
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

# Step 1: Get all sell orders of the user, to know which items to look at.
$userOrdersData = Invoke-Api "$baseUrl/orders/user/$userSlug"
Log("Order Data: $userOrdersData")
$userSellOrders = $userOrdersData.data | Where-Object { $_.type -eq "sell" }
Log("Sell Orders: $($userSellOrders.Count)")

foreach ($order in $userSellOrders) {
    $isFine = $true
    $itemSlug = Get-Item-Slug($order.itemId)
    Log("Got item slug: $itemSlug")

    if($itemSlug -eq "warhead") {
##      Personal breakpoint entry for easier debugging.
        Log("At breakpoint for $itemSlug")
    }

    # Step 2: Get all sell orders for the item
    # There is also /orders/item/$itemSlug/top for the top 5 orders. But that gives missleading
    # results if my order isn't in it. And there is no downside for getting all orders instead.
    $topOrdersData = Invoke-Api "$baseUrl/orders/item/$itemSlug"
    if (-not $topOrdersData) {
        Write-Output("Found no orders for $itemSlug.")
        continue
    }

    # TODO: Deal with mutliple orders of the same user?
    # Get the actual user price. The value from the user orders might be outdated.
    $userPrice = ($topOrdersData.data | Where-Object { $_.type -eq "sell" -and $_.user.slug -eq $userSlug }).platinum
    Log("User price: $userPrice")
    if(-not $userPrice -gt 0) {
        Write-Output("Found no current order for user, probably got removed recently: [$itemSlug]")
        continue
    }
    $userOrderUpdated = ($topOrdersData.data | Where-Object { $_.type -eq "sell" -and $_.user.slug -eq $userSlug }).updatedAt

    # Filter out offline orders, we only need to compete with online.
    # Also filter out our own orders.
    $topSellOrders = $topOrdersData.data | Where-Object { $_.type -eq "sell" -and $_.user.status -ne "offline" -and $_.user.slug -ne $userSlug }
    # Make sure the list is ordered by date and price. On the website, the newest order within the same price will be on top.
    $topSellOrders = $topSellOrders | Sort-Object -Property updatedAt -Descending | Sort-Object -Property platinum

    # Check how many same-price orders are ahead.
    # TODO: Maybe even ignore not-ingame orders? But if I am online, I want to check online. And maybe even ingame, if I am about to switch to it.
    #       But ingame is always at the top of the list, where all the action is happening.
    $samePriceMoreRecentCount = (@($topSellOrders | Where-Object { $_.platinum -eq $userPrice -and $_.updatedAt -gt $userOrderUpdated })).Count
    if ($samePriceMoreRecentCount -gt 0) {
        if($Priceorder) {
            Write-Output "User's sell order is behind $samePriceMoreRecentCount same-price offer(s) of $($userPrice) platinum: [$itemSlug]"
        }
        $isFine = $false
    }

    # Count how many orders are cheaper
    $cheaperCount = 0
    $cheaperCount = (@($topSellOrders | Where-Object { $_.platinum -lt $userPrice })).Count
    if ($cheaperCount -gt $OverpricedCount) {
        if($Overpriced) {
            Write-Output "There are $cheaperCount cheaper sell orders than the user's price of $($userPrice): [$itemSlug]"
        }
        $isFine = $false
    }

    # Check if the cheapest offer is at least 1 platinum higher than user's
    $lowestPrice = $topSellOrders[0].platinum
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

# TODO: move into function to then use for buy and sell.
# Check buy orders.
if($CheckBuy) {
    $userBuyOrders = $userOrdersData.data | Where-Object { $_.type -eq "buy" }
    foreach ($order in $userBuyOrders) {
        $isFine = $true
        $itemSlug = Get-Item-Slug($order.itemId)
        Log("Got buy item slug: $itemSlug")

        # Get all orders for the item
        $topOrdersData = Invoke-Api "$baseUrl/orders/item/$itemSlug"
        if (-not $topOrdersData) {
            Write-Output("Found no orders for $itemSlug.")
            continue
        }

        # Get the actual user price. The value from the user orders might be outdated.
        $userPrice = ($topOrdersData.data | Where-Object { $_.type -eq "buy" -and $_.user.slug -eq $userSlug }).platinum
        Log("User buy price: $userPrice")
        if(-not $userPrice -gt 0) {
            Write-Output("Found no current order for user, probably got removed recently: [$itemSlug]")
            continue
        }
        $userOrderUpdated = ($topOrdersData.data | Where-Object { $_.type -eq "buy" -and $_.user.slug -eq $userSlug }).updatedAt

        # Filter out offline orders, we only need to compete with online.
        # Also filter out our own orders.
        $topBuyOrders = $topOrdersData.data | Where-Object { $_.type -eq "buy" -and $_.user.status -ne "offline" -and $_.user.slug -ne $userSlug }
        # Make sure the list is ordered by date and price. On the website, the newest order within the same price will be on top.
        $topBuyOrders = $topBuyOrders | Sort-Object -Property updatedAt -Descending | Sort-Object -Property platinum -Descending

        # Check how many same-price orders are ahead.
        $samePriceMoreRecentCount = (@($topBuyOrders | Where-Object { $_.platinum -eq $userPrice -and $_.updatedAt -gt $userOrderUpdated })).Count
        if ($samePriceMoreRecentCount -gt 0) {
            if($Priceorder) {
                Write-Output "User's buy order is behind $samePriceMoreRecentCount same-price offer(s) of $($userPrice) platinum: [$itemSlug]"
            }
            $isFine = $false
        }

        if($isFine -and $Fine) {
            Write-Output "Item is fine with the price of $($userPrice): [$itemSlug]"
        }
    }
}

# Check Syndicate prices.
if($TopSyndicateMods -gt 0) {
    Write-Output("User orders done, getting Syndicate mods now.")
    # 20250621 list taken from wiki, syndicate offerings.
    $syndicates = @{
        "The Perrin Sequence" = @("razor_mortar","toxic_sequence","deadly_sequence","voltage_sequence","sequence_burn","sonic_fracture","resonance","savage_silence","resonating_quake","afterburn","everlasting_ward","vexing_retaliation","guardian_armor","guided_effigy","spectral_spirit","mach_crash","thermal_transfer","conductive_sphere","coil_recharge","cathode_current","balefire_surge","blazing_pillage","aegis_gale","desiccations_curse","elemental_sandstorm","negation_swarm","empowered_quiver","piercing_navigator","infiltrate","concentrated_arrow","greedy_pull","magnetized_discharge","counter_pulse","fracturing_crush","soul_survivor","creeping_terrify","despoil","shield_of_shadows","teeming_virulence","larva_burst","parasitic_vitality","insatiable","abundant_mutation","repair_dispensary","temporal_artillery","temporal_erosion","thrall_pact","mesmer_shield","blinding_reave","ironclad_charge","iron_shrapnel","piercing_roar","reinforcing_stomp","pool_of_life","vampire_leech","abating_link","champions_blessing","swing_line","eternal_war","prolonged_paralysis","hysterical_assault","enraged","tesla_bank","repelling_bastille","photon_repeater","shadow_haze","dark_propagation")
        "Red Veil" = @("jades_judgment","prismatic_companion","gleaming_blight","eroding_blight","stockpiled_blight","toxic_blight","seeking_shuriken","smoke_shadow","fatal_teleport","rising_storm","path_of_statues","tectonic_fracture","ore_gaze","titanic_rumbler","rubble_heap","recrystalize","spectral_spirit","fireball_frenzy","immolated_radiance","healing_flame","exothermic","warriors_rest","dread_ward","blood_forge","blending_talons","gourmand","hearty_nourishment","catapult","gastro","tribunal","warding_thurible","lasting_covenant","accumulating_whipclaw","venari_bodyguard","pilfering_strangledome","swift_bite","valence_formation","savior_decoy","damage_decoy","hushed_invisibility","safeguard_switch","irradiating_disarm","ballistic_bullseye","staggering_shield","muzzle_flash","mesas_waltz","soul_survivor","creeping_terrify","despoil","shield_of_shadows","venom_dose","revealing_spores","regenerative_molt","contagion_cloud","spellbound_harvest","beguiling_lantern","razorwing_blitz","ironclad_flight","shock_trooper","shocking_speed","transistor_shield","capacitance","prey_of_dynar","ulfruns_endurance","target_fixation","airburst_rounds","jet_stream","funnel_clouds","anchored_glide")
        "New Loka" = @("volatile_recompense","winds_of_purity","disarming_purity","bright_purity","lasting_purity","elusive_retribution","endless_lullaby","reactive_storm","duality","calm_and_frenzy","peaceful_provocation","energy_transfer","shattered_storm","mending_splinters","spectrosiphon","viral_tempest","tidal_impunity","rousing_plunder","pilfering_swarm","omikujis_fortune","wrath_of_ukko","swift_bite","valence_formation","greedy_pull","magnetized_discharge","counter_pulse","fracturing_crush","mind_freak","pacifying_bolts","chaos_sphere","assimilate","smite_infusion","hallowed_eruption","phoenix_renewal","hallowed_reckoning","partitioned_mallet","conductor","spellbound_harvest","beguiling_lantern","razorwing_blitz","ironclad_flight","axios_javelineers","intrepid_stand","pool_of_life","vampire_leech","abating_link","champions_blessing","swing_line","eternal_war","prolonged_paralysis","hysterical_assault","enraged","fused_reservoir","critical_surge","cataclysmic_gate","target_fixation","airburst_rounds","jet_stream","funnel_clouds","anchored_glide","celestial_stomp","enveloping_cloud","primal_rage","merulina_guardian","loyal_merulina","surging_blades")
        "Steel Meridian" = @("prismatic_companion","volatile_recompense","scattered_justice","justice_blades","neutralizing_justice","shattering_justice","path_of_statues","tectonic_fracture","ore_gaze","titanic_rumbler","rubble_heap","recrystalize","fireball_frenzy","immolated_radiance","healing_flame","exothermic","surging_dash","radiant_finish","furious_javelin","chromatic_blade","freeze_force","ice_wave_impedance","chilling_globe","icy_avalanche","biting_frost","dread_ward","blood_forge","blending_talons","gourmand","hearty_nourishment","catapult","gastro","accumulating_whipclaw","venari_bodyguard","pilfering_strangledome","wrath_of_ukko","ballistic_bullseye","staggering_shield","muzzle_flash","mesas_waltz","pyroclastic_flow","reaping_chakram","safeguard","divine_retribution","controlled_slide","teeming_virulence","larva_burst","parasitic_vitality","insatiable","abundant_mutation","neutron_star","antimatter_absorb","escape_velocity","molecular_fission","smite_infusion","hallowed_eruption","phoenix_renewal","hallowed_reckoning","wrecking_wall","fused_crucible","ironclad_charge","iron_shrapnel","piercing_roar","reinforcing_stomp","venom_dose","revealing_spores","regenerative_molt","contagion_cloud","prey_of_dynar","ulfruns_endurance","vampiric_grasp","the_relentless_lost")
        "Cephalon Suda" = @("razor_mortar","entropy_spike","entropy_flight","entropy_detonation","entropy_burst","sonic_fracture","resonance","savage_silence","resonating_quake","afterburn","everlasting_ward","vexing_retaliation","guardian_armor","guided_effigy","freeze_force","ice_wave_impedance","chilling_globe","icy_avalanche","biting_frost","balefire_surge","blazing_pillage","aegis_gale","viral_tempest","tidal_impunity","rousing_plunder","pilfering_swarm","empowered_quiver","piercing_navigator","infiltrate","concentrated_arrow","rift_haven","rift_torrent","cataclysmic_continuum","hall_of_malevolence","explosive_legerdemain","total_eclipse","pyroclastic_flow","reaping_chakram","safeguard","divine_retribution","controlled_slide","neutron_star","antimatter_absorb","escape_velocity","molecular_fission","partitioned_mallet","conductor","wrecking_wall","fused_crucible","thrall_pact","mesmer_shield","blinding_reave","shadow_haze","dark_propagation","tesla_bank","repelling_bastille","photon_repeater","fused_reservoir","critical_surge","cataclysmic_gate","vampiric_grasp","the_relentless_lost","merulina_guardian","loyal_merulina","surging_blades")
        "Arbiters of Hexis" = @("jades_judgment","gilded_truth","blade_of_truth","avenging_truth","stinging_truth","seeking_shuriken","smoke_shadow","fatal_teleport","rising_storm","elusive_retribution","endless_lullaby","reactive_storm","duality","calm_and_frenzy","peaceful_provocation","energy_transfer","surging_dash","radiant_finish","furious_javelin","chromatic_blade","warriors_rest","shattered_storm","mending_splinters","spectrosiphon","mach_crash","thermal_transfer","conductive_sphere","coil_recharge","cathode_current","tribunal","warding_thurible","lasting_covenant","desiccations_curse","elemental_sandstorm","negation_swarm","omikujis_fortune","rift_haven","rift_torrent","cataclysmic_continuum","savior_decoy","damage_decoy","hushed_invisibility","safeguard_switch","irradiating_disarm","hall_of_malevolence","explosive_legerdemain","total_eclipse","mind_freak","pacifying_bolts","chaos_sphere","assimilate","repair_dispensary","temporal_artillery","temporal_erosion","axios_javelineers","intrepid_stand","shock_trooper","shocking_speed","transistor_shield","capacitance","celestial_stomp","enveloping_cloud","primal_rage")
    }
    # Prepare result hashtable with top items for each syndicate.
    $syndicateResults = @{}
    # TODO: Combine cache and result? And only filter for the top X for the output?
    # Cache to avoid redundant API calls for duplicate mods across syndicates.
    $itemPriceCache = @{}

    foreach ($syndicate in $syndicates.Keys) {
        $itemResults = @()

        foreach ($itemSlug in $syndicates[$syndicate]) {
            # Check cache first
            if ($itemPriceCache.ContainsKey($itemSlug)) {
                $cachedPrice = $itemPriceCache[$itemSlug]
                if ($cachedPrice -ne $null) {
                    $itemResults += [PSCustomObject]@{
                        Item  = $itemSlug
                        Price = $cachedPrice
                    }
                    Log("Used cached price $cachedPrice plat for $itemSlug from $syndicate")
                } else {
                    Write-Output "No data for $itemSlug from $syndicate (cached null)."
                }
                continue
            }

            # Not cached, make API call.
            $itemData = Invoke-Api "$baseUrl/orders/item/$itemSlug"
            if (-not $itemData) {
                Write-Output "No data for $itemSlug from $syndicate."
                continue
            }

            # Filter sell orders for online/ingame users
            $sellOrders = $itemData.data | Where-Object { $_.type -eq "sell" -and $_.user.status -in @("online", "ingame") }

            if ($sellOrders.Count -lt 2) {
                Write-Output "Not enough orders for $itemSlug from $syndicate."
                continue
            }

            # Sort by platinum (ascending), then updatedAt (descending — newest order first at same price)
            $sortedOrders = $sellOrders | Sort-Object -Property updatedAt -Descending | Sort-Object -Property platinum

            # Get second cheapest price. As an attempt to avoid fake prices. Even if it is real, they might not respond, or sell it quickly.
            $secondCheapestPrice = $sortedOrders[1].platinum
            
            # Cache price
            $itemPriceCache[$itemSlug] = $secondCheapestPrice

            # Add result to list
            $itemResults += [PSCustomObject]@{
                Item  = $itemSlug
                Price = $secondCheapestPrice
            }
            Log("Found $secondCheapestPrice plat for $itemSlug from $syndicate")
        }

        # Get top 5 most expensive items for this syndicate
        $sortedItems = $itemResults | Sort-Object -Property Price -Descending

        if ($sortedItems.Count -ge $TopSyndicateMods) {
            $lastPrice = $sortedItems[$TopSyndicateMods-1].Price
            $topItems = $sortedItems | Where-Object { $_.Price -ge $lastPrice }
        } else {
            $topItems = $sortedItems
        }

        # Store in final results
        $syndicateResults[$syndicate] = $topItems

    }
    foreach ($syndicate in $syndicateResults.Keys) {
        $itemStrings = $syndicateResults[$syndicate] | ForEach-Object {
            "$($_.Item):$($_.Price)"
        }
        $line = "*$($syndicate)*: " + ($itemStrings -join ", ")
        Write-Output $line
    }
	# TODO: Also get the cheapest syndicate prices? To buy and resell them? But there are probably better things to flip.
	# TODO: Check for cheap ducates.
}
Write-Output "$((Get-Date).ToString('HH:mm:ss')) Program done."
