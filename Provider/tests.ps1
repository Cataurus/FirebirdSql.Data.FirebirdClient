param(
	[Parameter(Mandatory=$True)]$Configuration,
	[Parameter(Mandatory=$True)]$FirebirdSelection,
	[Parameter(Mandatory=$True)]$TestSuite)

$ErrorActionPreference = 'Stop'

$FirebirdConfiguration = @{
	FB30 = @{
		Download = 'https://www.dropbox.com/s/x46uy7e5zrtsnux/fb30.7z?dl=1';
		Executable = '.\firebird.exe';
		Args = @('-a');
	};
	FB25 = @{
		Download = 'https://www.dropbox.com/s/ayzjnxjx20vb7s5/fb25.7z?dl=1';
		Executable = '.\bin\fb_inet_server.exe';
		Args = @('-a', '-m');
	};
}

$baseDir = Split-Path -Parent $PSCommandPath
$testsBaseDir = "$baseDir\src\FirebirdSql.Data.FirebirdClient.Tests"
$testsNETDir = "$testsBaseDir\bin\$Configuration\net452"
$testsCOREDir = "$testsBaseDir\bin\$Configuration\netcoreapp3.0"

$startDir = $null
$firebirdProcess = $null

if ($env:tests_firebird_dir) {
	$firebirdDir = $env:tests_firebird_dir
}
else {
	$firebirdDir = 'I:\Downloads\fb_tests'
}

function Check-ExitCode($command) {
	& $command
	$exitCode = $LASTEXITCODE
	if ($exitCode -ne 0) {
		echo "Non-zero ($exitCode) exit code. Exiting..."
		exit $exitCode
	}
}

function Prepare() {
	$script:startDir = $pwd
	$selectedConfiguration = $FirebirdConfiguration[$FirebirdSelection]
	$fbDownload = $selectedConfiguration.Download
	$fbDownloadName = $fbDownload -Replace '.+/([^/]+)\?dl=1','$1'
	if (Test-Path $firebirdDir) {
		rm -Force -Recurse $firebirdDir
	}
	mkdir $firebirdDir | Out-Null
	cd $firebirdDir
	echo "Downloading $fbDownload"
	(New-Object System.Net.WebClient).DownloadFile($fbDownload, (Join-Path (pwd) $fbDownloadName))
	echo "Extracting $fbDownloadName"
	7z x -bsp0 -bso0 $fbDownloadName
	cp -Recurse -Force .\embedded\* $testsNETDir
	cp -Recurse -Force .\embedded\* $testsCOREDir
	rmdir -Recurse .\embedded
	rm $fbDownloadName
	mv .\server\* .
	rmdir .\server

	ni firebird.log -ItemType File | Out-Null

	echo "Starting Firebird"
	$script:firebirdProcess = Start-Process -FilePath $selectedConfiguration.Executable -ArgumentList $selectedConfiguration.Args -PassThru
}

function Cleanup() {
	cd $script:startDir
	$process = $script:firebirdProcess
	$process.Kill()
	$process.WaitForExit()
	rm -Force -Recurse $firebirdDir
}

function Tests-All() {
	Tests-FirebirdClient-NET
	Tests-FirebirdClient-Core
	Tests-EF6
	Tests-EFCore
}

function Tests-FirebirdClient-NET() {
	echo "=== $($MyInvocation.MyCommand.Name) ==="

	cd $testsNETDir
	Check-ExitCode { .\FirebirdSql.Data.FirebirdClient.Tests.exe --labels=All }

	echo "=== END ==="
}

function Tests-FirebirdClient-Core() {
	echo "=== $($MyInvocation.MyCommand.Name) ==="

	cd $testsCOREDir
	Check-ExitCode { dotnet FirebirdSql.Data.FirebirdClient.Tests.dll --labels=All }

	echo "=== END ==="
}

function Tests-EF6() {
	echo "=== $($MyInvocation.MyCommand.Name) ==="

	cd "$baseDir\src\EntityFramework.Firebird.Tests\bin\$Configuration\net452"
	Check-ExitCode { .\EntityFramework.Firebird.Tests.exe --labels=All }

	cd "$baseDir\src\EntityFramework.Firebird.Tests\bin\$Configuration\netcoreapp3.0"
	Check-ExitCode { dotnet EntityFramework.Firebird.Tests.dll --labels=All }

	echo "=== END ==="
}

function Tests-EFCore() {
	echo "=== $($MyInvocation.MyCommand.Name) ==="

	if ($FirebirdSelection -ne 'FB25') {
		cd "$baseDir\src\FirebirdSql.EntityFrameworkCore.Firebird.Tests\bin\$Configuration\netcoreapp2.2"
		Check-ExitCode { dotnet FirebirdSql.EntityFrameworkCore.Firebird.Tests.dll --labels=All }

		cd "$baseDir\src\FirebirdSql.EntityFrameworkCore.Firebird.FunctionalTests"
		Check-ExitCode { dotnet test --no-build -c $Configuration }
	}

	echo "=== END ==="
}

try {
	Prepare
	& $TestSuite
}
finally {
	Cleanup
}
