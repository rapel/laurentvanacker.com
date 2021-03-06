<#
This Sample Code is provided for the purpose of illustration only
and is not intended to be used in a production environment.  THIS
SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT
WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT
LIMITED TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS
FOR A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free
right to use and modify the Sample Code and to reproduce and distribute
the object code form of the Sample Code, provided that You agree:
(i) to not use Our name, logo, or trademarks to market Your software
product in which the Sample Code is embedded; (ii) to include a valid
copyright notice on Your software product in which the Sample Code is
embedded; and (iii) to indemnify, hold harmless, and defend Us and
Our suppliers from and against any claims or lawsuits, including
attorneys' fees, that arise or result from the use or distribution
of the Sample Code.
#>
#region Function definitions
Function Get-ScreenShot { 
	<#
			.SYNOPSIS
			Take screenshots from the screen(s) during a duration and interval when specified 

			.DESCRIPTION
			Take screenshots from the screen(s) during a duration and interval when specified

			.PARAMETER FullName
			The destination file when taking only one screenshoot (no duration and interval specified)

			.PARAMETER Directory
			The destination directory when taking mutliple screenshoots (duration and interval specified)

			.PARAMETER Format
			The image format 

			.PARAMETER DurationInSeconds
			The duration in seconds during which we will take a screenshot

			.PARAMETER IntervalInSeconds
			The interval in seconds between two screenshots (when DurationInSeconds is specified)

			.PARAMETER Area
			The are of the screenshot : 'WorkingArea' is for the current screen and 'VirtualScreen' is for all connected screens

			.PARAMETER Beep
			Play a beep everytime a screenshot is taken if specified

			.PARAMETER QualityLevel
			The Quality/Compression level of the saved picture

			.EXAMPLE
			Get-ScreenShot
			Take a screenshot of the current screen. The file will be generated in the Pictures folder of the current user and will use the PNG format by default. The filename will use the YYYYMMDDTHHmmSS format

			.EXAMPLE
            Get-ScreenShot -FullName 'c:\temp\screenshot.gif' -Area VirtualScreen
			Take a screenshot of all connected screens. The generated file will be 'c:\temp\screenshot.wmf'

			.EXAMPLE
            Get-ScreenShot -Directory 'C:\temp' -Format jpg -QualityLevel 100 -DurationInSeconds 30 -IntervalInSeconds 10 -Area WorkingArea -Format JPG -Verbose
			Take multiple screenshots (of the current screen) during a 30 seconds period by waiting 10 second between two shots. The compression level is set to 100 (Best). The file will be generated in the C:\temp folder and will use the JPG format by default. The filename will use the YYYYMMDDTHHmmSS format

	#>	
	[CmdletBinding(DefaultParameterSetName = 'Directory', PositionalBinding = $false)]
	Param(
		[Parameter(ParameterSetName = 'File')]
		[Parameter(Mandatory = $false, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False)]
		[ValidateScript( { $_ -match "\.($($(([Drawing.Imaging.ImageCodecInfo]::GetImageEncoders()).Filenameextension -split ";" | ForEach-Object { $_.replace('*.','')}) -join '|'))$" })]
		[string]$FullName,

		[Parameter(ParameterSetName = 'Directory')]
		[Parameter(Mandatory = $false, ValueFromPipeline = $False, ValueFromPipelineByPropertyName = $False)]
		[string]$Directory,

		<#
		[Parameter(ParameterSetName='Directory')]
		[parameter(Mandatory=$false)]
		[ValidateScript({$_ -in [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders().FormatDescription})]
		[String]$Format='JPEG',
        #>

		[Parameter(ParameterSetName = 'Directory')]
		[parameter(Mandatory = $false)]
		[uint32]$DurationInSeconds = 0,

		[Parameter(ParameterSetName = 'Directory')]
		[parameter(Mandatory = $false)]
		[uint32]$IntervalInSeconds = 0,

		[parameter(Mandatory = $false)]
		[ValidateSet('VirtualScreen', 'WorkingArea')]
		[String]$Area = 'WorkingArea',

		[parameter(Mandatory = $false)]
		[ValidateScript( { $_ -in 0..100 })]
		[uint32]$QualityLevel = 100,

		[parameter(Mandatory = $false)]
		[Switch]$Beep,

		[parameter(Mandatory = $false)]
        [uint32] $sourceX, 

		[parameter(Mandatory = $false)]
        [uint32] $SourceY, 

		[parameter(Mandatory = $false)]
        [int] $sourceWidth, 

		[parameter(Mandatory = $false)]
        [int] $sourceHeight
	)

	#Dynamic parameter to fill the list of known Formats (Dynamic paramater is just used here for autocompletion :) )
	DynamicParam {
		# Create the dictionary 
		$RuntimeParameterDictionary = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameterDictionary

		# Create the collection of attributes
		$AttributeCollection = New-Object -TypeName System.Collections.ObjectModel.Collection[System.Attribute]

		# Create and set the parameters' attributes
		$Attributes = New-Object -TypeName System.Management.Automation.ParameterAttribute
		$Attributes.Mandatory = $false
		$Attributes.ParameterSetName = 'Directory'
		
		# Add the attributes to the attributes collection
		$AttributeCollection.Add($Attributes)
		
		# Generate and set the ValidateSet 
		$ValidateSet = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders().FormatDescription
		$ValidateSetAttribute = New-Object -TypeName System.Management.Automation.ValidateSetAttribute -ArgumentList ($ValidateSet)
		
		# Add the ValidateSet to the attributes collection
		$AttributeCollection.Add($ValidateSetAttribute)
		
		# Create and return the dynamic parameter
		$Format = New-Object -TypeName System.Management.Automation.RuntimeDefinedParameter -ArgumentList ('Format', [string], $AttributeCollection)		
		$RuntimeParameterDictionary.Add('Format', $Format)
		return $RuntimeParameterDictionary 
	}
	
	begin {
		Add-Type -AssemblyName System.Windows.Forms
		Add-Type -AssemblyName System.Drawing
	}

	process {
		# Gather Screen resolution information
		#$Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
		#$Screen = [System.Windows.Forms.SystemInformation]::WorkingArea
		$Screen = [System.Windows.Forms.SystemInformation]::$Area
		$TimeElapsed = 0
		$IsTimeStampedFileName = $false
		if ($Format -is [System.Management.Automation.RuntimeDefinedParameter]) {
			if ([string]::IsNullOrWhiteSpace($Format.Value)) {
				$Format = "JPEG"
			}
			else {
				$Format = $Format.Value
			}
		}
		if ($FullName) {
			$Directory = Split-Path -Path $FullName -Parent
			$HasExtension = $FullName -match "\.(?<Extension>\w+)$"
			if ($HasExtension) {
				$Format = $Matches['Extension']
			}
			$null = New-Item -Path $Directory -ItemType Directory -Force
		}
		elseif ($Directory) {
			$null = New-Item -Path $Directory -ItemType Directory -Force
			$FullName = Join-Path -Path $Directory -ChildPath $($Area + "_" + (Get-Date -f yyyyMMddTHHmmss) + ".$Format")
			$IsTimeStampedFileName = $true
		}
		else {
			$Directory = [Environment]::GetFolderPath('MyPictures')
			Write-Verbose "Target directory not specified we use [$Directory]"
			$FullName = Join-Path -Path $Directory -ChildPath $($Area + "_" + (Get-Date -f yyyyMMddTHHmmss) + ".$Format")
			$IsTimeStampedFileName = $true
		}

		do 
        {
            if (($sourceX -le 0) -or ($sourceX -gt $Screen.Width))
            { 
                $sourceX = $Screen.Left 
            }
            if (($sourceY -le 0) -or ($sourceY -gt $Screen.Height)) 
            {
                $sourceY = $Screen.Top 
            }
            if (($sourceWidth -le 0) -or ($sourceWidth -gt $Screen.Width)) 
            { 
                $sourceWidth = $Screen.Width
            }
            if (($sourceHeight -le 0) -or ($sourceHeight -gt $Screen.Height))  
            {
                $sourceHeight = $Screen.Height
            }

            if (($sourceWidth -gt 0) -and ($sourceHeight -gt 0))
            { 
                 $Size = [System.Drawing.Size]::new($sourceWidth, $sourceHeight)
            }
            else
            {
                $Size = $Bitmap.Size
            }

            Write-Verbose "`$sourceX      : $sourceX"
            Write-Verbose "`$sourceY      : $sourceY"
            Write-Verbose "`$sourceWidth  : $sourceWidth"
            Write-Verbose "`$sourceHeight : $sourceHeight"
            # Create bitmap using the top-left and bottom-right bounds
            #$Bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $Screen.Width, $Screen.Height
			$Bitmap = New-Object -TypeName System.Drawing.Bitmap -ArgumentList $SourceWidth, $SourceHeight

			# Create Graphics object
			$Graphic = [System.Drawing.Graphics]::FromImage($Bitmap)
            
			# Capture screen
			$Graphic.CopyFromScreen($sourceX, $sourceY, 0, 0, $Size)

            $QualityEncoder = [System.Drawing.Imaging.Encoder]::Quality
            $EncoderParameters = New-Object System.Drawing.Imaging.EncoderParameters(1)

            # Set JPEG quality level here: 0 - 100 (inclusive bounds)
            $EncoderParameters.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter($QualityEncoder, $QualityLevel)

			# Save to file
			$ImageEncoder = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatDescription -eq $Format }
			$Bitmap.Save($FullName, $ImageEncoder, $EncoderParameters) 
			Write-Host -Object "[$(Get-Date -Format T)] Screenshot saved to $FullName"
			if ($Beep) {
				[console]::beep()
			}
	    
			if (($DurationInSeconds -gt 0) -and ($IntervalInSeconds -gt 0)) {
				Write-Verbose "[$(Get-Date -Format T)] Sleeping $IntervalInSeconds seconds ..."
				Start-Sleep -Seconds $IntervalInSeconds
				$TimeElapsed += $IntervalInSeconds
			}
			if ($IsTimeStampedFileName) {
				$FullName = Join-Path -Path $Directory -ChildPath $($Area + "_" + (Get-Date -f yyyyMMddTHHmmss) + ".$Format")
			}
		} While ($TimeElapsed -lt $DurationInSeconds) 
	}	
	end {
	}
}    
#endregion

Clear-Host
New-Alias -Name New-ScreenShoot -Value Get-ScreenShot -ErrorAction SilentlyContinue
#Get-ScreenShot -Verbose
Get-ScreenShot -Directory 'C:\temp' -Format JPEG -QualityLevel 100 -DurationInSeconds 180 -IntervalInSeconds 2 -Area WorkingArea -Beep -Verbose
#Get-ScreenShot -Directory 'C:\temp' -Format JPEG -QualityLevel 100 -DurationInSeconds 180 -IntervalInSeconds 2 -Area WorkingArea -sourceX 100 -SourceY 100 -sourceWidth 1024 -sourceHeight 768 -Beep -Verbose
#Get-ScreenShot -FullName 'c:\temp\screenshot.gif' -Verbose
#Get-ScreenShot -Verbose