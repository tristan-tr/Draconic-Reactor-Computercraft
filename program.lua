-- Modifiable variables
local reactorSide = "back"
local outputGateSide = "right"
local emergencyChargeGateSide = "top"

local targetFieldPercentage = 50
local targetTemperatureRange = {7950, 8000}

local monitorUpdateTime = 0.1 -- seconds
-- DONT CHANGE AFTER THIS

local sleepTime = 0.05 -- one tick

-- Shutdown when these get hit to avoid meltdown
local maxTemperature = 8200
local lowestFieldPercentage = 15

local monitor = peripheral.find("monitor")
local inputFluxGate = peripheral.find("flux_gate")
local outputFluxGate = peripheral.wrap(outputGateSide)
local emergencyChargeGate = peripheral.wrap(emergencyChargeGateSide)
local reactor = peripheral.wrap(reactorSide)


if inputFluxGate == nil then
	error("Input flux gate is not connected to the network.")
end
if outputFluxGate == nil then
	error("Output flux gate is not on the "..outputGateSide.." of the computer. Either change the side or move the flux gate.")
end
if reactor == nil then
	error("Reactor stabilizer is not on the "..reactorSide.." of the computer. Either change the side or move the reactor stabilizer.")
end

local usingMonitor = true
if monitor == nil then
	usingMonitor = false
end

local emergencyChargeIsSetup = true
if emergencyChargeGate == nil then
	emergencyChargeIsSetup = false
end

os.loadAPI("GraphicsAPI")

local saturationPercentage, fieldPercentage, fuelPercentage
local lastEmergencyAction = "None."

-- Monitor update function
function updateTerm(reactorInfo)
	GraphicsAPI.resetScreen()

	-- Reactor Status
	statusColor = colors.green
	if reactorInfo.status == "warming_up" then
		statusColor = colors.orange
	else
		if reactorInfo.status == "cold" then
			statusColor = colors.lightBlue
		end
	end

	GraphicsAPI.writeText("Reactor Status", {2, 2}, colors.white)
	GraphicsAPI.writeTextRight(string.upper(reactorInfo.status), {1, 2}, statusColor)

	-- RF Generation
	GraphicsAPI.writeText("RF Generation", {2, 4}, colors.white)
	GraphicsAPI.writeTextRight(tostring(math.floor(reactorInfo.generationRate)).." rf/t", {1, 4}, colors.green)

	-- Temperature
	temperatureColor = colors.green
	if reactorInfo.temperature > maxTemperature - 500 then
		temperatureColor = colors.orange
	end
	if reactorInfo.temperature > maxTemperature then
		temperatureColor = colors.red
	end

	GraphicsAPI.writeText("Temperature", {2, 6}, colors.white)
	-- Format our temperature string to be with 2 decimals and ends with celcius
	GraphicsAPI.writeTextRight(string.format("%.2f", reactorInfo.temperature).."C", {1, 6}, temperatureColor)


	-- Input gate
	GraphicsAPI.writeText("Input Gate", {2, 8}, colors.white)
	GraphicsAPI.writeTextRight(tostring(math.floor(inputFluxGate.getSignalLowFlow())).." rf/t", {1, 8}, colors.green)

	-- Output gate
	GraphicsAPI.writeText("Output Gate", {2, 9}, colors.white)
	GraphicsAPI.writeTextRight(tostring(math.floor(outputFluxGate.getSignalLowFlow())).." rf/t", {1, 9}, colors.green)

	-- Saturation
	GraphicsAPI.writeText("Saturation", {2,11}, colors.white)
	GraphicsAPI.writeTextRight(string.format("%.2f", saturationPercentage).."%", {1, 11}, colors.green)
	GraphicsAPI.drawProgressBar({2, 12}, term.getSize() - 4, saturationPercentage, colors.blue, colors.gray)

	-- Field Strength
	fieldColor = colors.green
	if targetFieldPercentage - fieldPercentage > 5 then
		fieldColor = colors.red
	end
	GraphicsAPI.writeText("Field Strength", {2, 14}, colors.white)
	GraphicsAPI.writeTextRight(string.format("%.2f", fieldPercentage).."%", {1, 14}, fieldColor)
	GraphicsAPI.drawProgressBar({2,15}, term.getSize() - 4, fieldPercentage, fieldColor, colors.gray)

	-- Fuel percentage
	fuelColor = colors.green
	if fuelPercentage < 70 then
		fuelColor = colors.orange
	end
	if fuelPercentage < 30 then
		fuelColor = colors.red
	end
	GraphicsAPI.writeText("Fuel Percentage", {2, 17}, colors.white)
	GraphicsAPI.writeTextRight(string.format("%.2f", fuelPercentage).."%", {1,17}, fuelColor)
	GraphicsAPI.drawProgressBar({2,18}, term.getSize() - 4, fuelPercentage, fuelColor, colors.gray)

	-- Write the last emergency that got handled automatically
	GraphicsAPI.writeText("Last Emergency Action: "..lastEmergencyAction, {1,19}, colors.gray)
end

local function updateReactor(reactorInfo)
  -- Rapidly increase temperature until we are in our range, then keep our flux output the same as the generation rate to avoid temperature loss
  if reactorInfo.temperature >= targetTemperatureRange[1] and reactorInfo.temperature <= targetTemperatureRange[2] then
  	outputFluxGate.setSignalLowFlow(reactorInfo.generationRate - saturationPercentage)
  else
	-- Rapidly increase temperature, but not too fast (temperature increase is based on saturation so we account for that)
  	outputFluxGate.setSignalLowFlow(reactorInfo.generationRate * (1 + (saturationPercentage / 100)))
  end
  inputFluxGate.setSignalLowFlow(reactorInfo.fieldDrainRate / (1 - (targetFieldPercentage/100)))
end

-- Main loop
while true do
	for i=1,monitorUpdateTime/sleepTime do
		reactorInfo = reactor.getReactorInfo()

		saturationPercentage = (reactorInfo.energySaturation / reactorInfo.maxEnergySaturation) * 100
		fieldPercentage = reactorInfo.fieldStrength / 1000000
		fuelConversion = reactorInfo.fuelConversion / reactorInfo.maxFuelConversion
		fuelPercentage = 100 - (fuelConversion * 100)

		updateTerm(reactorInfo)

		if reactorInfo.status == "running" then
			updateReactor(reactorInfo)
		else
			if reactorInfo.status == "warming_up" then
				-- We are charging so we need to set our input gate to allow RF
				inputFluxGate.setSignalLowFlow(200000)
			end
		end

		-- Safety features
		-- Stop when out of fuel
		if fuelPercentage < 10 then
			reactor.stopReactor()
			lastEmergencyAction = "Fuel < 10"
		end

		-- Stop when the temperature is too high
		if reactorInfo.temperature > maxTemperature then
			reactor.stopReactor()
			lastEmergencyAction = "Temperature > "..maxTemperature
		end

		-- Field percentage is too low, we need to emergency charge
		if fieldPercentage < lowestFieldPercentage and reactorInfo.status == "running" or reactorInfo.status == "cooling" then
			reactor.stopReactor()
			if emergencyChargeIsSetup then
				reactor.chargeReactor()
				emergencyChargeGate.setSignalLowFlow(10000000)
			end
			lastEmergencyAction = "Field Percentage < "..lowestFieldPercentage
		else
			if emergencyChargeIsSetup then
			emergencyChargeGate.setSignalLowFlow(0)
			end
		end

		sleep(sleepTime)
	end


	-- We only update our monitor every second to avoid lag
	if usingMonitor then
		-- Write to our monitor
		terminal = term.redirect(monitor)
		updateTerm(reactorInfo)
		-- Write to our terminal next time we write
		term.redirect(terminal)
	end
end
