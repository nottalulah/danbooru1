function init()
{
	var prefSvc = Components.classes["@mozilla.org/preferences-service;1"].getService(Components.interfaces.nsIPrefBranch);
	var ml = document.getElementById('danbooru');
	ml.selectedIndex = -1;
	ml.removeAllItems();
	gDanbooruManager.init(ml);

	document.getElementById('tags').focus();

	if (prefSvc.getBoolPref("extensions.danbooruUp.fileurlsource") || !(window.arguments[0].imageURI.scheme == 'file') )
	{
		document.getElementById('source').value = window.arguments[0].imageURI.spec;
	}
}

function doOK()
{
	var ml = document.getElementById('danbooru');
	var tags = document.getElementById('tags').value;
	var rating = ['Explicit','Questionable','Safe'][document.getElementById('ratinggrp').selectedIndex];
	gDanbooruManager.selectDanbooru(ml.selectedIndex);
	gDanbooruManager.uninit();

	var helpersvc= Components.classes["@unbuffered.info/danbooru/helper-service;1"]
			.getService(Components.interfaces.danbooruIHelperService);
	if(tags.length) {
		// compact tag input
		var tagarr=tags.replace(/\s\s+/g, ' ').replace(/^\s+|\s+$/g,'').split(' ');
		var flat=[];
		var needupdate = false;
		for(var a in tagarr) {
			flat[tagarr[a]]=null;
		}
		try {
			var tagHist = helpersvc.tagService;
			for(var a in flat) {
				if (!tagHist.incrementValueForName(a))
					needupdate = true;
			}
		} catch(e) {
			// silently fail
		}
		var prefService		= Components.classes["@mozilla.org/preferences-service;1"]
					.getService(Components.interfaces.nsIPrefBranch);
		needupdate = prefService.getBoolPref("extensions.danbooruUp.autocomplete.update.afterdialog") && needupdate;
	}

	helpersvc.startUpload(
			window.arguments[0].imageURI,
			document.getElementById('source').value,
			tags,
			rating,
			ml.label,
			window.arguments[0].imageLocation,
			window.arguments[0].wind,
			needupdate
		);
	window.arguments[0].imageLocation = null;
	window.arguments[0].wind = null;
	window.arguments=null;

	return true;
}
function doCancel() {
	return true;
}
function refocus() {
	this.removeEventListener("focus",refocus,false);
	setTimeout(function(){window.focus()},10);
}
function doSwitchTab() {
	var tab = window.arguments[0].wind;
	var currentTab = tab.linkedBrowser.getTabBrowser().selectedTab;

	// the easy way, but not the right way:
	// 	tab.linkedBrowser.getTabBrowser().ownerDocument.__parent__.focus();
	var browserWindow = tab.linkedBrowser.contentWindow
				.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
					.getInterface(Components.interfaces.nsIWebNavigation)
				.QueryInterface(Components.interfaces.nsIDocShellTreeItem)
					.rootTreeItem
				.QueryInterface(Components.interfaces.nsIInterfaceRequestor)
					.getInterface(Components.interfaces.nsIDOMWindow);

	// tab (but not window) switching is on a timeout of 0 so we have to wait until we're blurred before refocusing
	browserWindow.addEventListener("focus",refocus,false);

	if (currentTab != tab) {
		tab.linkedBrowser.getTabBrowser().selectedTab = tab;
	} else {
		browserWindow.focus();
	}

	return true;
}
