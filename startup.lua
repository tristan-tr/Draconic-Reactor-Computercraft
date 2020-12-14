-- Download both of our files and start our program
function downloadFile(name, url)
	file = fs.open(name, "w")
	file.write(http.get(url).readAll())
	file.close()
end

apiURL = "https://raw.githubusercontent.com/tristan-tr/Draconic-Reactor-Computercraft/main/GraphicsAPI.lua"
programURL = "https://raw.githubusercontent.com/tristan-tr/Draconic-Reactor-Computercraft/main/program.lua"

downloadFile("GraphicsAPI", apiURL)
downloadFile("program", programURL)

shell.run("program")
