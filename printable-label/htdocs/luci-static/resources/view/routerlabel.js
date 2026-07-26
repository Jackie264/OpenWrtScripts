'use strict';
'require view';
'require ui';
'require fs';
'require uci';
'require rpc';
'require routerlabel';

// Kept in sync with PKG_VERSION in this app's Makefile by build-apk.sh
// (run automatically before every build, or on its own via
// `build-apk.sh --sync-version`) -- can't be derived at runtime since this
// file is also used directly (as loose files, no SDK build) during
// day-to-day development.
var APP_VERSION = '0.2.0';

var callSystemBoard = rpc.declare({
	object: 'system',
	method: 'board'
});

var callSystemInfo = rpc.declare({
	object: 'system',
	method: 'info'
});

// Fixed sample values for local development -- lets you check layout/styling
// changes without needing a real wifi setup or reconfiguring uci each time.
// No redeploy needed to toggle: just add ?mock=1 to the page URL in the
// browser (e.g. .../admin/services/routerlabel?mock=1).
function getMockData() {
	return {
		device: 'Linksys E8450 (UBI)',
		openwrtVersion: 'OpenWrt 23.05.5 r24106-10cc5fcd00',
		flashram: '16MB/128MB',
		hostname: 'Belkin-RT3200',
		dnstld: 'local',
		lanip: '192.168.253.1',
		wifiSsid: 'My Wifi SSID',
		wifiPw: '<no password>'
	};
}

// Fetches everything from ubus/uci/fs and assembles it into the same plain
// object shape getMockData() returns, so render() never needs to know or
// care whether it's looking at real or mock data.
function loadRealData() {
	return Promise.all([
		L.resolveDefault(callSystemBoard(), null),
		L.resolveDefault(callSystemInfo(), null),
		L.resolveDefault(fs.read('/proc/mtd'), ''),
		uci.load(['system', 'network', 'dhcp', 'wireless'])
	]).then(function (results) {
		var board = results[0];
		var info = results[1];
		var mtdText = results[2];

		if (!board || !info) {
			return null;
		}

		var flashBytes = routerlabel.parseMtdFlashBytes(mtdText || '');
		var ramBytes = (info.memory && info.memory.total) || 0;

		var ifaces = (uci.sections('wireless', 'wifi-iface') || []).map(function (s) {
			return { disabled: s.disabled, ssid: s.ssid, key: s.key };
		});
		var wifi = routerlabel.pickWifi(ifaces);

		var wifiSsid, wifiPw;
		if (wifi) {
			wifiSsid = wifi.ssid || '';
			wifiPw = routerlabel.formatWifiPw(wifi.key);
		} else {
			wifiSsid = 'unknown';
			wifiPw = 'unknown';
		}

		return {
			device: board.model || '',
			openwrtVersion: (board.release && board.release.description) || '',
			flashram: routerlabel.getFlashRamLabel(flashBytes, ramBytes),
			hostname: uci.get('system', '@system[0]', 'hostname') || '',
			dnstld: uci.get('dhcp', '@dnsmasq[0]', 'domain') || '',
			lanip: uci.get('network', 'lan', 'ipaddr') || '',
			wifiSsid: wifiSsid,
			wifiPw: wifiPw
		};
	});
}

// Print only .rl-print-area (the table + power-brick label), not the page's
// intro text, "why is this safe" text, or the print button itself. Standard
// "hide everything, then re-reveal the print area" pattern -- visibility
// (not display) so LuCI's own page chrome doesn't reflow before printing.
var PRINT_CSS = '' +
	'@media print {' +
	'  body * { visibility: hidden !important; }' +
	'  .rl-print-area, .rl-print-area * { visibility: visible !important; }' +
	'  .rl-print-area { position: absolute; left: 0; top: 0; line-height: 1.2; }' +
	'}' +
	'.rl-page { padding: 5px; }' +
	'.rl-label-wrapper { display: inline-block; }' +
	'.rl-print-area { padding: 1em; }' +
	// .rl-table-wrap wraps only the table (not the button) so its width --
	// and therefore .rl-print-area/.rl-label-wrapper's shrink-wrapped width,
	// and therefore .rl-power-brick's 100%-width match below -- is driven
	// by the table alone. The button is taken out of flow entirely
	// (position: absolute) so it can sit beside the table without widening
	// this box; a flex row here previously made the whole box (and so the
	// power-brick box under it) as wide as table+button combined, which is
	// wider than the table by itself.
	'.rl-table-wrap { position: relative; }' +
	'.rl-print-btn { position: absolute; top: 0; left: 100%; margin-left: 5px; }' +
	'.rl-table { border: 1px solid #ccc; border-radius: 8px; border-collapse: separate; border-spacing: 0; padding: 5px; }' +
	'.rl-table td { padding: 2px 10px; }' +
	'.rl-table td.rl-label { text-align: right; white-space: nowrap; font-weight: bold; }' +
	'.rl-power-brick { margin-top: 1.5em; padding: calc(0.75em + 5px); border: 1px solid #ccc; border-radius: 8px; }' +
	'.rl-pwinput { font: inherit; border: 1px solid #ccc; padding: 2px 4px; box-sizing: border-box; width: 10em; }' +
	'.rl-pw-hint { font-size: 0.85em; color: #666; margin-left: 0.6em; }' +
	'.rl-pw-print-fallback { display: none; }' +
	'@media print {' +
	'  .rl-pwinput { border: none; padding: 0; background: transparent; }' +
	'  .rl-pw-hint { display: none; }' +
	'  .rl-print-btn { display: none; }' +
	'}';

return view.extend({
	load: function () {
		if (/[?&]mock=1(&|$)/.test(window.location.search)) {
			return Promise.resolve(getMockData());
		}
		return loadRealData();
	},

	// LuCI's base View class (which view.extend() builds on) already defines
	// handleSave/handleSaveApply/handleReset itself, and addFooter() checks
	// `this.handleSaveApply || this.handleSave || this.handleReset` -- so
	// simply not overriding them isn't enough, since they're still inherited
	// and truthy (confirmed by reading addFooter() straight out of the
	// router's luci.js). All three must be explicitly nulled out here to
	// shadow the inherited defaults and suppress the Save & Apply/Save/Reset
	// footer, since this page never writes to uci.
	handleSave: null,
	handleSaveApply: null,
	handleReset: null,

	render: function (data) {
		if (!data) {
			ui.addNotification(null, E('p', {}, _('Could not load router label data.')), 'danger');
			return E('p', {}, _('Could not load router label data.'));
		}

		// Matches the script exactly, including the trailing "." when
		// dnstld is unset (script: "http://$HOSTNAME.$LOCALDNSTLD" with
		// no fallback) -- don't special-case an empty dnstld here, or the
		// LAN address will silently diverge from print-router-label.sh's
		// output on routers with no dhcp domain configured.
		var fqdn = data.hostname + '.' + data.dnstld;
		var today = new Date().toISOString().slice(0, 10);

		var pwInput = E('input', {
			'class': 'rl-pwinput',
			type: 'text',
			placeholder: '?'
		});

		var pwHint = E('span', { 'class': 'rl-pw-hint' },
			[ 'Password never saved - only shown on the label' ]);

		// Hidden on screen; always swapped in for the <input> while printing
		// (never the input itself, even when filled in) -- an <input>'s own
		// intrinsic line-height/box-model doesn't quite match plain text
		// even with border/padding stripped for print, which showed up as
		// slightly taller spacing on this one row only when it had a value.
		// Plain text via a <span> sidesteps that entirely and matches every
		// other row's height exactly, whether blank or filled in (the typed
		// value). Blank rather than "<no password>" when empty -- unlike the
		// Wifi PW row, an unset Login PW just means nobody filled it in yet,
		// not that the router genuinely has no password.
		var pwPrintFallback = E('span', { 'class': 'rl-pw-print-fallback' }, ['']);

		window.addEventListener('beforeprint', function () {
			pwPrintFallback.textContent = pwInput.value.trim();
			pwInput.style.display = 'none';
			pwPrintFallback.style.display = 'inline';
		});
		window.addEventListener('afterprint', function () {
			pwInput.style.display = '';
			pwPrintFallback.style.display = 'none';
		});

		var rows = [
			['Device', data.device],
			['Flash/RAM', data.flashram],
			['OpenWrt', data.openwrtVersion],
			['Browse to', 'http://' + fqdn],
			['SSH to', 'ssh root@' + fqdn],
			['LAN Address', data.lanip],
			['User', 'root'],
			['Login PW', [ pwInput, pwPrintFallback, ' ', pwHint ]],
			['Wifi SSID', data.wifiSsid],
			['Wifi PW', data.wifiPw],
			['Date printed', today],
			['Printed with', 'Printable Label v' + APP_VERSION + ', https://github.com/richb-hanover/OpenWrtScripts']
		];

		var table = E('table', { 'class': 'rl-table' }, rows.map(function (row) {
			var label = row[0], value = row[1];
			// Value may be a single string/node, or (for the Login PW row) an
			// array of several. Wrap each non-node item in a string so LuCI's
			// dom.append() text-nodes/appends it rather than assigning to
			// innerHTML -- these values come from uci config or ubus (device
			// name, hostname, wifi SSID/key) and can contain characters like
			// "<no password>" that would otherwise be parsed as markup. DOM
			// nodes are appended as-is.
			var items = Array.isArray(value) ? value : [ value ];
			var content = items.map(function (item) {
				return (item && item.nodeType) ? item : String(item);
			});
			var valueCell = E('td', {}, content);
			return E('tr', {}, [
				E('td', { 'class': 'rl-label' }, [ label + ':' ]),
				valueCell
			]);
		}));

		var printButton = E('button', {
			'class': 'cbi-button cbi-button-action rl-print-btn',
			'click': function () { window.print(); }
		}, [ _('Print') ]);

		return E('div', { 'class': 'rl-page' }, [
			E('style', {}, [ PRINT_CSS ]),
			E('h2', {}, _('Printable label for your router')),
			E('p', {}, _('Print this page to produce a paper label (like the one below) that displays the Router ' +
				'model, OpenWrt version, LAN address and the credentials necessary to access the ' +
				'router. ' +
				'Tape the label to the router so that years from now, the next person to touch ' +
				'the router (it might be you) can access it. ' +
				'If you wish, type the password into the Login PW field. It will be printed, but never saved. ')),
			E('p', {}, [
				E('strong', {}, [ _('Pro tip:') ]),
				_(' Snip out the router\'s model from the Power Brick Label and tape it to the power brick so it ' +
					'can be re-united with the router if they get separated.')
			]),
			E('h3', {}, _('Why is this trustworthy?')),
			E('p', {}, _('This page only displays data retrieved from the router; ' +
				'it never acts on it or sends it anywhere. If the bad guy can read this label, ' +
				'they can also factory-reset the router (or steal your TV or your silverware).')),
			E('p', {}, _('If you are concerned, don\'t print this label.')),
			E('div', { 'class': 'rl-label-wrapper' }, [
				E('div', { 'class': 'rl-print-area' }, [
					E('div', { 'class': 'rl-table-wrap' }, [
						table,
						printButton
					]),
					E('div', { 'class': 'rl-power-brick' }, [
						E('strong', {}, [ _('Power Brick Label: ') ]),
						E('span', {}, [ data.device ])
					])
				])
			])
		]);
	}
});
