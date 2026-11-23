'use strict';
'require view';

/* Services -> xguard VPN: embeds the xguard UI (/xguard/) and hands it the LuCI session,
   so no second login is needed. */
return view.extend({
	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	render: function() {
		/* the unique query string keeps the browser from showing a cached (older) copy of the page */
		var url = '/xguard/?v=' + Date.now() + '#sid=' + encodeURIComponent((L.env && L.env.sessionid) || '');

		return E('div', { 'class': 'cbi-map' }, [
			E('p', { 'style': 'margin:.4em 0' }, [
				E('a', { 'href': url, 'target': '_blank', 'rel': 'noopener' }, _('Open in a new tab'))
			]),
			E('iframe', {
				'src': url,
				'title': 'xguard',
				'style': 'width:100%;height:calc(100vh - 14rem);min-height:640px;border:1px solid var(--border-color-medium, #ccc);border-radius:4px;background:#fff'
			})
		]);
	}
});
