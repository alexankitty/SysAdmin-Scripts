@echo off
    setlocal enableextensions disabledelayedexpansion

    set "file=%~1"

    rem Separate path and filename
    for %%a in ("%file%") do ( set "filePath=%%~dpa" & set "fileName=%%~nxa" )

    rem Change to target path and adapt file path if sucessful
    pushd "%filePath%" && (for %%a in (.\) do set "filePath=%%~fa")||(set "filePath=")

    rem If the current directory has changed, get file data and return to previous folder
    if defined filePath (

        set "vers="
        FOR /F "tokens=2 delims==" %%a in ('
            wmic datafile where "name='%filePath:\=\\%%fileName%'" get Version /value 
        ') do set "vers=%%a"
  
    	popd
    )

    endlocal & set "vers=%vers%"
