-- Modifiable variables
local reactorSide = "back"
local outputGateSide = "right"
local emergencyChargeGateSide = "top"

local targetFieldPercentage = 50
local targetTemperature = 8000

local autoActivate = true
-- DONT CHANGE AFTER THIS

-- Shutdown when these get hit to avoid meltdown
local maxTemperature = 8200
local lowestFieldPercentage = 20

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
	saturationPercentage = (reactorInfo.energySaturation / reactorInfo.maxEnergySaturation) * 100
	GraphicsAPI.writeText("Saturation", {2,11}, colors.white)
	GraphicsAPI.writeTextRight(string.format("%.2f", saturationPercentage).."%", {1, 11}, colors.green)
	GraphicsAPI.drawProgressBar({2, 12}, term.getSize() - 4, saturationPercentage, colors.blue, colors.gray)

	-- Field Strength
	fieldPercentage = reactorInfo.fieldStrength / 1000000
	fieldColor = colors.green
	if targetFieldPercentage - fieldPercentage > 5 then
		fieldColor = colors.orange
	end
	if targetFieldPercentage - fieldPercentage > 20 then
		fieldColor = colors.red
	end
	GraphicsAPI.writeText("Field Strength", {2, 14}, colors.white)
	GraphicsAPI.writeTextRight(string.format("%.2f", fieldPercentage).."%", {1, 14}, fieldColor)
	GraphicsAPI.drawProgressBar({2,15}, term.getSize() - 4, fieldPercentage, fieldColor, colors.gray)

	-- Fuel percentage
	fuelPercentage = 100 - ((reactorInfo.fuelConversion / reactorInfo.maxFuelConversion) * 100)
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

-- Main loop
while true do
	reactorInfo = reactor.getReactorInfo()

	if usingMonitor then
		-- Write to our monitor
		terminal = term.redirect(monitor)
		updateTerm(reactorInfo)
		-- Write to our terminal
		term.redirect(terminal)
	end
	updateTerm(reactorInfo)


	if reactorInfo.status == "running" then
		-- Change our input gate to keep field strength at our target
		inputFluxGate.setSignalLowFlow(reactorInfo.fieldDrainRate / (1 - (targetFieldPercentage / 100)))

		-- Change our output gate to keep temperature at our target
		outputFluxGate.setSignalLowFlow(reactorInfo.generationRate + targetTemperature - reactorInfo.temperature)
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
			emergencyChargeGate.setSignalLowFlow(200000)
		end
		lastEmergencyAction = "Field Percentage < "..lowestFieldPercentage
	else
		if emergencyChargeIsSetup then
		emergencyChargeGate.setSignalLowFlow(0)
		end
	end

	sleep(0.1)
end
