<?xml version='1.0' encoding='UTF-8'?>
<Project Type="Project" LVVersion="25008000">
	<Property Name="NI.LV.All.SaveVersion" Type="Str">25.0</Property>
	<Property Name="NI.LV.All.SourceOnly" Type="Bool">true</Property>
	<Item Name="My Computer" Type="My Computer">
		<Property Name="server.app.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.control.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="server.tcp.enabled" Type="Bool">false</Property>
		<Property Name="server.tcp.port" Type="Int">0</Property>
		<Property Name="server.tcp.serviceName" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.tcp.serviceName.default" Type="Str">My Computer/VI Server</Property>
		<Property Name="server.vi.callsEnabled" Type="Bool">true</Property>
		<Property Name="server.vi.propertiesEnabled" Type="Bool">true</Property>
		<Property Name="specify.custom.address" Type="Bool">false</Property>
		<Item Name="ctls" Type="Folder">
			<Item Name="Server Data.ctl" Type="VI" URL="../Server Data.ctl"/>
			<Item Name="Server FGV Modes.ctl" Type="VI" URL="../Server FGV Modes.ctl"/>
		</Item>
		<Item Name="SubVIs" Type="Folder">
			<Item Name="Prompts" Type="Folder">
				<Item Name="Buy Any.vi" Type="VI" URL="../Buy Any.vi"/>
				<Item Name="Find Best Trending Stock.vi" Type="VI" URL="../Find Best Trending Stock.vi"/>
			</Item>
			<Item Name="tools" Type="Folder">
				<Item Name="Buy Stock.vi" Type="VI" URL="../Buy Stock.vi"/>
				<Item Name="Get History Chart.vi" Type="VI" URL="../Get History Chart.vi"/>
				<Item Name="Get Owned Stocks.vi" Type="VI" URL="../Get Owned Stocks.vi"/>
				<Item Name="Get Stock Names.vi" Type="VI" URL="../Get Stock Names.vi"/>
				<Item Name="Get Stock Prices.vi" Type="VI" URL="../Get Stock Prices.vi"/>
				<Item Name="Get Wallet.vi" Type="VI" URL="../Get Wallet.vi"/>
			</Item>
			<Item Name="Add Stock Price.vi" Type="VI" URL="../Add Stock Price.vi"/>
			<Item Name="Server FGV.vi" Type="VI" URL="../Server FGV.vi"/>
		</Item>
		<Item Name="main.vi" Type="VI" URL="../main.vi"/>
		<Item Name="Dependencies" Type="Dependencies"/>
		<Item Name="Build Specifications" Type="Build"/>
	</Item>
</Project>
