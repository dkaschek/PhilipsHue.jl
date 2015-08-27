module PhilipsHue

using JSON, Requests, Compat

export  PhilipsHueBridge, getIP, getbridgeconfig, isinitialized,
        getlights, getlight, setlight, setlights, testlights,
        register, initialize

type PhilipsHueBridge
  ip::String
  username:: String
  function PhilipsHueBridge(ip, username)
    new(ip, username)
  end
end

"""
Read the bridge's settings from the [meethue.com]("https://www.meethue.com/api/nupnp") website.

Returns the IP address if available.

    getIP()
"""

function getIP()
	response = get("https://www.meethue.com/api/nupnp")
    # this url sometimes redirects, we should follow...
	if response.status == 302
	    println("trying curl instead, in case of redirects")
        bridgeinfo = JSON.parse(readall(`curl -sL http://www.meethue.com/api/nupnp`))
	else
	    bridgeinfo = JSON.parse(response.data)
	end
	return bridgeinfo[1]["internalipaddress"]
end

"""
Read the current bridge configuration. For example:

    B = PhilipsHueBridge("192.168.1.90", "yourusername")
    getbridgeconfig(B)
"""

function getbridgeconfig(bridge::PhilipsHueBridge)
    response = get("http://$(bridge.ip)/api/$(bridge.username)/config")
	return JSON.parse(response.data)
end

"""
Return true if the bridge has been initialized, and there is a connection to the portal.

    isinitialized(bridge::PhilipsHueBridge)
"""
function isinitialized(bridge::PhilipsHueBridge)
	if get(getbridgeconfig(bridge), "portalconnection", "not connected") == "connected"
	  return true
	else
	  return false
	end
end

"""
Return the current setting of all lights connected to the bridge.

    getlights(bridge::PhilipsHueBridge)
"""

function getlights(bridge::PhilipsHueBridge)
    response = get("http://$(bridge.ip)/api/$(bridge.username)/lights")
 	return JSON.parse(response.data)
end

"""
Return the settings of the specified light.

    getlight(bridge::PhilipsHueBridge, light=1)
"""

function getlight(bridge::PhilipsHueBridge, light=1)
    response = get("http://$(bridge.ip)/api/$(bridge.username)/lights/$(string(light))")
 	responsedata = JSON.parse(response.data)

 	# println("data for light $light: $responsedata")
 	# not all Hue lights have sat/hue!
    if responsedata["type"] == "Dimmable light"
        return (
            responsedata["state"]["on"],
            responsedata["state"]["bri"])
    elseif responsedata["type"] == "Extended color light"
        return (
            responsedata["state"]["on"],
            responsedata["state"]["sat"],
            responsedata["state"]["bri"],
            responsedata["state"]["hue"])
    end
end

"""
Set a light by passing a dictionary of settings.

eg Dict{Any,Any}("on" => true, "sat" => 123, "bri" => 123, "hue" => 123),
"hue" is from 0 to 65280 (?), "sat" and "bri" are saturation and brightness from 0 to 255,
0 is red, yellow is 12750, green is 25500, blue is 46920, etc.

If keys are omitted, that aspect of the light won't be changed.

Keys are strings, values can be numeric and will get converted to strings

    setlight(B, 1, Dict{Any,Any}("on" => true))
    setlight(B, 3, Dict{Any,Any}("on" => false))
    setlight(B, 2, Dict{Any,Any}("on" => true, "sat" => 123, "bri" => 243, "hue" => 123)

"""

function setlight(bridge::PhilipsHueBridge, light::Int, settings::Dict)
  state = AbstractString[]
  for (k, v) in settings
     push!(state, ("\"$k\": $(string(v))"))
  end
  state = "{" * join(state, ",") * "}"
  response = put("http://$(bridge.ip)/api/$(bridge.username)/lights/$(string(light))/state", data="$(state)")
  return JSON.parse(response.data)
end

"""

Set all lights in a group by passing a dictionary of settings.

eg Dict{Any,Any}("on" => true, "sat" => 123, "bri" => 123, "hue" => 123),
"hue" is from 0 to 65280 (?), "sat" and "bri" are saturation and brightness from 0 to 255,
0 is red, yellow is 12750, green is 25500, blue is 46920, etc.

If keys are omitted, that aspect of the light won't be changed.

Keys are strings, values can be numeric and will get converted to strings

    setlights(B, Dict{Any,Any}("on" => true))
    setlights(B, Dict{Any,Any}("on" => false))
    setlights(B, Dict{Any,Any}("on" => true, "sat" => 123, "bri" => 243, "hue" => 123)

"""

function setlights(bridge::PhilipsHueBridge, settings::Dict)
    state = AbstractString[]
    for (k, v) in settings
        push!(state,("\"$k\": $(string(v))"))
    end
    state = "{" * join(state, ",") * "}"
    response = put("http://$(bridge.ip)/api/$(bridge.username)/groups/0/action", data="$(state)")
    return JSON.parse(response.data)
end

function register(bridge_ip; devicetype="juliascript", username="juliauser1")
    #A username. If this is not provided, a random key will be generated and returned in the response.
    #Important! The username will soon be deprecated in the bridge. It is strongly recommended not to use
    # this and use the randomly generated bridge username.

    # returns the randomly generated key, or "" on failure

    response     = post("http://$(bridge_ip)/api/"; data="{\"devicetype\":\"$(devicetype)#$(username)\"}")
    responsedata = JSON.parse(response.data)
    # responsedata is probably:
    # 1-element Array{Any,1}:
    # ["error"=>["type"=>101,"description"=>"link button not pressed","address"=>"/"]]
    if responsedata[1][first(keys(responsedata[1]))]["description"] == "link button not pressed"
        println("register(): Quick, you have ten seconds to press the button on the bridge!")
        sleep(10)
        response = post("http://$(bridge_ip)/api/"; data="{\"devicetype\":\"$(devicetype)#$(username)\"}")
        responsedata = JSON.parse(response.data)
        if first(keys(responsedata[1])) == "success"
            println("register(): Successfully registered $devicetype and $username with the bridge at $bridge_ip")
            # returns username which is randomly generated key
            username = responsedata[1]["success"]["username"]
            return username
        else
            warn("register(): Failed to register $devicetype#$username with the bridge at $bridge_ip")
            return ""
        end
    end
end

"""
Initialize a bridge, supplying devicetype and username. Registering this script with the bridge
may require you to run to the bridge and press the button.

For example:

    B = PhilipsHueBridge("192.168.1.90", "yourusername")
    initialize(bridge::PhilipsHueBridge; devicetype="juliascript", username="juliauser1")
"""

function initialize(bridge::PhilipsHueBridge; devicetype="juliascript", username="juliauser1")
    println("initialize(): Trying to get the IP address of the Philips bridge.")
    ipaddress = getIP()
    bridge.ip = ipaddress
    println("initialize(): Found bridge at $(bridge.ip).")
    println("initialize(): Trying to register $devicetype with the bridge at $(bridge.ip)...")
    username = register(bridge.ip, devicetype=devicetype, username=username)
    if ! isempty(username)
        println("initialize(): Registration successful")
        bridge.username = username
        return true
    else
        warn("initialize(): Registration failed")
        return false
    end
end

"""
Test all lights.

    testlights(bridge::PhilipsHueBridge, total=5)
"""

function testlights(bridge::PhilipsHueBridge, total=5)
    for i in 1:total
        setlights(bridge, Dict{Any,Any}("on" => false))
        sleep(1)
        setlights(bridge, Dict{Any,Any}("on" => true))
        sleep(1)
    end
    setlights(bridge, Dict{Any,Any}("hue" => 10000, "sat" => 64, "bri" => 255))
end

end # module
