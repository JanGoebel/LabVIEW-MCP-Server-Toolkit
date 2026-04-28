<?xml version='1.0' encoding='UTF-8'?>
<Project Type="Project" LVVersion="20008000">
	<Property Name="NI.LV.All.SaveVersion" Type="Str">20.0</Property>
	<Property Name="NI.LV.All.SourceOnly" Type="Bool">true</Property>
	<Property Name="NI.Project.Description" Type="Str"></Property>
	<Item Name="My Computer" Type="My Computer">
		<Property Name="NI.SortType" Type="Int">3</Property>
		<Property Name="server.app.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.control.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.tcp.enabled" Type="Bool">false</Property>
		<Property Name="server.tcp.port" Type="Int">0</Property>
		<Property Name="server.tcp.serviceName" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.tcp.serviceName.default" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.vi.callsEnabled" Type="Bool">true</Property>
		<Property Name="server.vi.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="specify.custom.address" Type="Bool">false</Property>
		<Item Name="sub VIs" Type="Folder">
			<Item Name="Acquire Signals.vi" Type="VI" URL="../sub VIs/Acquire Signals.vi"/>
			<Item Name="Get Log Path.vi" Type="VI" URL="../sub VIs/Get Log Path.vi"/>
			<Item Name="Globals.vi" Type="VI" URL="../sub VIs/Globals.vi"/>
			<Item Name="Log Data.vi" Type="VI" URL="../sub VIs/Log Data.vi"/>
		</Item>
		<Item Name="tools" Type="Folder">
			<Item Name="Get Waveform.vi" Type="VI" URL="../tools/Get Waveform.vi"/>
			<Item Name="Start Logging.vi" Type="VI" URL="../tools/Start Logging.vi"/>
			<Item Name="Stop Logging.vi" Type="VI" URL="../tools/Stop Logging.vi"/>
			<Item Name="Read Log.vi" Type="VI" URL="../tools/Read Log.vi"/>
		</Item>
		<Item Name="prompts" Type="Folder">
			<Item Name="Log Prompt.vi" Type="VI" URL="../prompts/Log Prompt.vi"/>
		</Item>
		<Item Name="Datalogger Main.vi" Type="VI" URL="../Datalogger Main.vi"/>
		<Item Name="readme.md" Type="Document" URL="../readme.md"/>
		<Item Name="Dependencies" Type="Dependencies"/>
		<Item Name="Build Specifications" Type="Build"/>
	</Item>
</Project>
