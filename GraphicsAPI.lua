function resetScreen()
	term.setTextColor(colors.white)
	term.setBackgroundColor(colors.black)
	term.clear()
	term.setCursorPos(1,1)
end

function writeText(text, startCoords, color)
	term.setCursorPos(startCoords[1], startCoords[2])
	term.setTextColor(color)
	term.write(text)
end

function writeTextRight(text, offsetCoords, color)
	local maxX, maxY = term.getSize()

	writeText(text, {maxX - offsetCoords[1] - string.len(text), offsetCoords[2]}, color)
end

function drawLine(startCoords, endCoords, color)
	-- paintutils.drawLine() changes the background color
	oldColor = term.getBackgroundColor()
	paintutils.drawLine(startCoords[1], startCoords[2], endCoords[1], endCoords[2], color)
	term.setBackgroundColor(oldColor)
end

-- Draws two overlapping lines
function drawProgressBar(startCoords, length, percentage, color, backgroundColor)
	drawLine(startCoords, {startCoords[1] + length, startCoords[2]}, backgroundColor)
	progressCoords = {startCoords[1] + math.floor((percentage / 100) * length), startCoords[2]}
	drawLine(startCoords, progressCoords, color)
end
