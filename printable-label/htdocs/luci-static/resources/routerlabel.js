'use strict';
'require baseclass';

// Pure data-parsing/formatting logic for Printable Label, ported from
// print-router-label.sh. Loaded by the LuCI JS view via 'require routerlabel'.
//
// This must be a genuine baseclass.extend() result -- LuCI's require()
// loader (compileClass() in luci.js) rejects anything that doesn't satisfy
// Class.isSubclass(), so a hand-rolled constructor function isn't enough
// (confirmed on-router: that got "factory yields invalid constructor").
// This is the same pattern fs.js/uci.js use.
//
// Unit-tested from tests/test_routerlabel_util.js, which loads this exact
// file under Node with a minimal baseclass.extend() shim -- see that file
// for why a plain require() of this file doesn't work under Node.

return baseclass.extend({
	// Round a byte count up to the next power of two, in whole MB.
	// Rounding up (rather than to nearest) accounts for /proc/mtd reporting
	// slightly less than the nominal hardware size.
	roundUpToPow2Mb: function (bytes) {
		var pow2 = 1;
		while (pow2 < bytes) {
			pow2 = pow2 * 2;
		}
		return Math.floor(pow2 / 1024 / 1024);
	},

	// Parse /proc/mtd content and return the size (bytes) of the largest
	// partition. The "dev:  size  erasesize  name" header line is skipped
	// naturally: its "size" column isn't hex digits, so the regex doesn't
	// match it, same as the Lua/shell versions of this logic.
	parseMtdFlashBytes: function (text) {
		var flashbytes = 0;
		var lines = text.split('\n');
		for (var i = 0; i < lines.length; i++) {
			var m = lines[i].match(/^([^:]+):\s+([0-9a-fA-F]+)/);
			if (m) {
				var bytes = parseInt(m[2], 16);
				if (!isNaN(bytes) && bytes > flashbytes) {
					flashbytes = bytes;
				}
			}
		}
		return flashbytes;
	},

	// Combine flash + RAM byte counts into the "16MB/128MB" label string.
	getFlashRamLabel: function (flashbytes, membytes) {
		var flashmb = this.roundUpToPow2Mb(flashbytes);
		var rammb = this.roundUpToPow2Mb(membytes);
		return flashmb + 'MB/' + rammb + 'MB';
	},

	// Given an ordered list of {disabled, ssid, key} wifi-iface entries,
	// return the first enabled one, or null if none are enabled.
	pickWifi: function (ifaces) {
		for (var i = 0; i < ifaces.length; i++) {
			if (ifaces[i].disabled !== '1') {
				return ifaces[i];
			}
		}
		return null;
	},

	// Format a wifi key for display: the literal key, or "<no password>"
	// if the iface has no key set (open wifi).
	formatWifiPw: function (key) {
		if (key === null || key === undefined || key === '') {
			return '<no password>';
		}
		return key;
	}
});
