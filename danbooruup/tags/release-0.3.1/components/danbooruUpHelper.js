const DANBOORUUPHELPER_CLASSNAME = "danbooruHelperService";
const DANBOORUUPHELPER_CONTRACTID = "@unbuffered.info/danbooru/helper-service;1";
const DANBOORUUPHELPER_CID = Components.ID("{d989b279-ba03-4b12-adac-925c7f0c4b9d}");

const Cc = Components.classes;
const Ci = Components.interfaces;

const prefService	= Cc["@mozilla.org/preferences-service;1"].getService(Ci.nsIPrefService);
const prefBranch	= Cc["@mozilla.org/preferences-service;1"].getService(Ci.nsIPrefBranch);
const ioService		= Cc["@mozilla.org/network/io-service;1"].getService(Ci.nsIIOService);
const promptService	= Cc["@mozilla.org/embedcomp/prompt-service;1"].getService(Ci.nsIPromptService);
const obService		= Cc["@mozilla.org/observer-service;1"].getService(Ci.nsIObserverService);

const cMinTagUpdateInterval = 1 * 60 * 1000;

function alert(msg)
{
	promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), msg);
}

function danbooruUpHitch(ctx, what)
{
	return function() { return ctx[what].apply(ctx, arguments); }
}

function __log(msg) {
	Components.classes["@mozilla.org/consoleservice;1"].getService(Components.interfaces.nsIConsoleService).logStringMessage(msg);
}

Cc["@mozilla.org/moz/jssubscript-loader;1"].getService(Ci.mozIJSSubScriptLoader)
	.loadSubScript("chrome://danbooruup/content/uploader.js");

ResultWrapper = function(result) { this._result = result; }
ResultWrapper.prototype = {
	_result: null,
	getMatchCount: function() {
		return this._result.matchCount;
	},
	getValueAt: function(i) {
		return this._result.getValueAt(i);
	},
	getStyleAt: function(i) {
		return this._result.getStyleAt(i);
	}
};

var danbooruUpHelperObject = {
	_tagService: null,
	_updating: false,
	_interactive: false,

	get tagService()
	{
		return this._tagService;
	},
	set tagService(s)
	{
		throw "tagService is a read-only property";
	},

	startup: function()
	{
		Cc["@mozilla.org/moz/jssubscript-loader;1"]
			.getService(Ci.mozIJSSubScriptLoader)
			.loadSubScript("chrome://global/content/XPCNativeWrapper.js");

		this._danbooruUpMsg = Cc['@mozilla.org/intl/stringbundle;1'].getService(Ci.nsIStringBundleService)
					.createBundle('chrome://danbooruup/locale/danbooruUp.properties');

		//obService.addObserver(this, "danbooru-options-changed", false);

		this._branch = prefService.getBranch("extensions.danbooruUp.");
		this._branch.QueryInterface(Components.interfaces.nsIPrefBranch2);
		this._branch.addObserver("", this, false);

		try {
			this._tagService = Cc["@unbuffered.info/danbooru/taghistory-service;1"]
						.getService(Ci.danbooruITagHistoryService);
		} catch (e) {
			var check = {};
			if(!this._branch.getBoolPref("suppressComponentAlert"))
			{
				promptService.alertCheck(null, this._danbooruUpMsg.GetStringFromName('danbooruUp.err.title'),
						this._danbooruUpMsg.GetStringFromName('danbooruUp.err.ac.component'),
						this._danbooruUpMsg.GetStringFromName('danbooruUp.dont.remind'),
						check);
				if (check.value) {
					this._branch.setBoolPref("suppressComponentAlert", true);
				}
			}
		}

		this.startupUpdate();

		this.loadScripts();
	},
	unregister: function()
	{
		if(this._branch)
			obService.removeObserver(this, "");
	},

	//
	// danbooruTagUpdater
	//
	mMaxID:-1,
	mTimer:null,

	/*
	browserWindows:[],
	registerBrowser: function(browserWin) {
		var existing;

		for (var i = 0; existing = this.browserWindows[i]; i++) {
			if (existing == browserWin) {
				throw new Error("Browser window has already been registered.");
			}
		}
this.log('registering a '+browserWin+'('+this.browserWindows.length+')');
		this.browserWindows.push(browserWin);
this.log('now have '+this.browserWindows.length);
	},

	unregisterBrowser: function(browserWin) {
		var existing;

		for (var i = 0; existing = this.browserWindows[i]; i++) {
			if (existing == browserWin) {
				this.browserWindows.splice(i, 1);
				return;
			}
		}
this.log(this.browserWindows.length+' after unregistering');

		throw new Error("Browser window is not registered.");
	},
	/**/

	getMaxID: function()
	{
		try {
			return this.tagService.maxID;
		} catch(e) {
			promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.maxid'));
		}
		return 0;
	},
	observe: function(aSubject, aTopic, aData)
	{
		//var os	= Components.classes["@mozilla.org/observer-service;1"]
		//	.getService(Components.interfaces.nsIObserverService);
		//os.removeObserver(this, "browser-window-before-show");
		//this.log("observing"+"\n"+aSubject + "\n" + aTopic + "\n" + aData);
		switch (aTopic) {
		case "app-startup":
			// cat. "app-startup"/topic "app-startup" is too soon, since we
			// need to open the DB file in the profile directory
			//
			// "profile-after-change" seems to be too soon also, as the cache service
			// also listens for this, but we get the notification first
			obService.addObserver(this, "final-ui-startup", false);
			break;
		case "final-ui-startup":
			obService.removeObserver(this, "final-ui-startup");
			this.startup();
			break;
		case "nsPref:changed":
			this.startTimer();
			this.setTooltipCrop();
			break;
		}
	},
	setTooltipCrop: function() {
		var cropping = prefBranch.getCharPref("extensions.danbooruUp.tooltipcrop");
		var wm = Cc['@mozilla.org/appshell/window-mediator;1'].getService(Ci.nsIWindowMediator);
		var en = wm.getEnumerator("navigator:browser");

		// hackish, but setting it to an empty string is equivalent to "none"
		if (cropping == "default") cropping = 'end';

		// loop through all browser windows and change crop attribute
		while (en.hasMoreElements())
		{
			var w = en.getNext();
			if (w.document.getElementById("aHTMLTooltip")) {
				w.document.getElementById("aHTMLTooltip").setAttribute("crop",cropping);
			}
		}
	},
	startTimer: function()
	{
		if (this.mTimer)
			this.mTimer.cancel();
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.update.ontimer"))
			return;
		this.mTimer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
		this.mTimer.initWithCallback(this, prefBranch.getIntPref("extensions.danbooruUp.autocomplete.update.interval")*60*1000, this.mTimer.TYPE_REPEATING_SLACK);
	},
	startupUpdate: function()
	{
		if (!this.tagService) return;
		var full = true;
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.enabled"))
			return;
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.update.onstartup"))
			return;
		if (prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.update.faststartup") &&
			this.tagService.rowCount > 0) {
			full = false;
			this.mMaxID = this.getMaxID();
		}
		prefBranch.setIntPref("extensions.danbooruUp.autocomplete.update.lastupdate", Date.now());
		this.update(full, false);
	},
	notify: function(aTimer)
	{
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.enabled"))
			return;
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.update.ontimer"))
		{
			aTimer.cancel();
			this.mTimer = null;
			return;
		}
		this.update(false, false);
	},
	update: function(aFull, aInteractive)
	{
		if (!this.tagService) return Components.results.NS_ERROR_NOT_AVAILABLE;
		if (!prefBranch.getIntPref("extensions.danbooruUp.autocomplete.update.lastupdate") && (prefBranch.getIntPref("extensions.danbooruUp.autocomplete.update.lastupdate") < Date.now() + cMinTagUpdateInterval))
		{
			dump("skipping tag update, " + (Date.now() + cMinTagUpdateInterval - prefBranch.getIntPref("extensions.danbooruUp.autocomplete.update.lastupdate")) + " seconds left\n");
			return;
		}

		var locationURL;
		try {
			locationURL = ioService.newURI(prefBranch.getCharPref("extensions.danbooruUp.updateuri"), '', null)
					.QueryInterface(Ci.nsIURL);
		} catch (e) {
			if(aInteractive)
				promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
			else
				return e.result
		}

		if(this.mMaxID>0 && !aFull)
		{
			locationURL.query = "after_id="+(this.mMaxID+1);
		}
		dump("using " + locationURL.spec + "\n");

		this._updating = true;
		this._interactive = aInteractive;
		try {
			this.tagService.updateTagListFromURI(locationURL.spec, true);
		} catch (e) {
			if(e.result==Components.results.NS_ERROR_NOT_AVAILABLE)
			{
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.updatebusy'));
				return e.result
			}
			else {
				this._updating = false;
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
				else
					return e.result
			}
		}
		this._updating = false;
		this.mMaxID = this.getMaxID();
		prefBranch.setIntPref("extensions.danbooruUp.autocomplete.update.lastupdate", Date.now());

		if (prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.update.ontimer") && !this.mTimer)
		{
			this.startTimer();
		}
		return Components.results.NS_OK;
	},
	cleanup: function(aInteractive)
	{
		var locationURL	= ioService.newURI(prefBranch.getCharPref("extensions.danbooruUp.updateuri"), '', null)
				.QueryInterface(Ci.nsIURL);
		try {
			this.tagService.updateTagListFromURI(locationURL.spec, false);
		} catch (e) {
			if(e.result==Components.results.NS_ERROR_NOT_AVAILABLE)
			{
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.updatebusy'));
			}
			else {
				promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
			}
		}
	},

	//
	//
	//
	startUpload: function(aRealSource, aSource, aTags, aRating, aDest, aLocation, aWind, aUpdate)
	{
		var uploader;
		var imgChannel	= ioService.newChannelFromURI(aRealSource);

		if (aRealSource.scheme == "file") {
			imgChannel.QueryInterface(Components.interfaces.nsIFileChannel);
			uploader = new danbooruUploader(aRealSource, aSource, aTags, aRating, aDest, aWind, true, aWind.linkedBrowser.contentDocument.location, aUpdate);
			// add entry to the observer
			obService.addObserver(uploader, "danbooru-down", false);
			imgChannel.asyncOpen(uploader, imgChannel);
		} else {
			var cookieJar	= Components.classes["@mozilla.org/cookieService;1"]
				.getService(Components.interfaces.nsICookieService);
			var cookieStr = cookieJar.getCookieString(aLocation, null);

			imgChannel.QueryInterface(Components.interfaces.nsIHttpChannel);
			imgChannel.referrer = aLocation;
			imgChannel.setRequestHeader("Cookie", cookieStr, true);

			// don't need to bother with Uploader's array transfer
			var listener = Components.classes["@mozilla.org/network/simple-stream-listener;1"]
				.createInstance(Components.interfaces.nsISimpleStreamListener);
			uploader = new danbooruUploader(aRealSource, aSource, aTags, aRating, aDest, aWind, false, aWind.linkedBrowser.contentDocument.location, aUpdate);

			// add entry to the observer
			obService.addObserver(uploader, "danbooru-down", false);
			listener.init(uploader.mOutStr, uploader);
			imgChannel.asyncOpen(listener, imgChannel);
		}
	},

	//
	// danbooruSiteAutocompleter
	//
	script_src:[],
	script_ins:'',
	files: ["chrome://danbooruup/content/extra/prototype.js",
		"chrome://danbooruup/content/extra/effects.js",
		"chrome://danbooruup/content/extra/controls.js",
		"chrome://danbooruup/content/extra/du-autocompleter.js"
		],
	// load scripts as strings to hopefully save some minor amount of processing time
	// at the cost of memory
	loadScripts: function (e)
	{
		if(this.script_src.length) return;
		try {
			for(var i=0; i < this.files.length; i++) {
				var script = ioService.newURI(this.files[i],null,null)
				this.script_src.push(this.getContents(script));
			}
			this.script_ins = this.getContents(ioService.newURI("chrome://danbooruup/content/extra/ac-insert.js",null,null));
		} catch(x) { Components.utils.reportError(x); }
	},

	contentLoaded: function (win)
	{
		// only putting the check here is lazy, but works
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.enabled"))
			return;
		if (!prefBranch.getBoolPref("extensions.danbooruUp.autocomplete.site.enabled"))
			return;

		var unsafeWin = win.wrappedJSObject;
		var unsafeLoc = new XPCNativeWrapper(unsafeWin, "location").location;
		var href = new XPCNativeWrapper(unsafeLoc, "href").href;
		var winUri = ioService.newURI(href, null, null);

		var sites = prefBranch.getCharPref("extensions.danbooruUp.postadduri").split("`");

		// determine injection based on URI and elements
		for (var i = 0; i < sites.length; ++i) {
			try {
				var uri = ioService.newURI(sites[i], null, null);
				if (winUri.prePath != uri.prePath) continue;
				//this.log(winUri.spec+' matched ' + uri.spec);
				if (winUri.path.match(/\/post\/(list|view|add)(\?|\/|$)/) || 
					winUri.path.match(/\/tag\/(mass_edit|rename|aliases|implications|set_type)(\/|$)/)) {
					this.inject(href, unsafeWin);
					return;
				}
				if ((new XPCNativeWrapper(unsafeWin)).document.getElementById("static-index"))
				{
					this.inject(href, unsafeWin);
					return;
				}
			} catch(x) {}
		}
		return;
	},

	searchTags: function (s, l)
	{
		res = Cc["@unbuffered.info/danbooru/taghistory-service;1"]
			.getService(Ci.danbooruITagHistoryService).searchTags(s, l);
		wrap = new ResultWrapper(res);
		return wrap;
	},

	inject: function (url, unsafeContentWin)
	{
		// we want our prototype/effects/control.js scripts to run in a sandbox
		var safeWin = new XPCNativeWrapper(unsafeContentWin);
		var sandbox = new Components.utils.Sandbox(safeWin);
		sandbox.window = safeWin;
		sandbox.document = sandbox.window.document;
		sandbox.unsafeWindow = unsafeContentWin;
		sandbox.GM_log = danbooruUpHitch(this, "log");
		sandbox.danbooruUpSearchTags = danbooruUpHitch(this, "searchTags");
		sandbox.__proto__ = safeWin;

		// put useful declarations into style array inside sandbox
		const TAGTYPE_COUNT = 5;
		var rx = new RegExp("s*(background(-w+)?|border(-w+)?|color|font(-w+)?|padding(-w+)?|letter-spacing|margin(-w+)?|outline(-w+)?|text(-w+)?)s*:.*;$","gm");
		var prefs = prefService.getBranch("extensions.danbooruUp.tagtype.");

		Components.utils.evalInSandbox("var style_arr = [];", sandbox);
		for(var i=0, rule; i<TAGTYPE_COUNT; i++) {
			rule = prefs.getCharPref(i).replace(/[{}]/g, '').match(rx).join('');
			Components.utils.evalInSandbox("style_arr['"+ i +"'] = atob('"+ safeWin.btoa(rule) +"');", sandbox);
			rule = prefs.getCharPref(i+".selected").replace(/[{}]/g, '').match(rx).join('');
			Components.utils.evalInSandbox("style_arr['"+ i +".selected'] = atob('"+ safeWin.btoa(rule) +"');", sandbox);
		}

		try {
			// load in the source from the content package
			Components.utils.evalInSandbox("var script_arr = [];", sandbox);
			for(var i=0; i < this.script_src.length; i++) {
				sandbox.script_arr.push(this.script_src[i]);
			}

			// load in the inserter script
			var lineFinder = new Error();
			Components.utils.evalInSandbox(this.script_ins, sandbox);
		} catch (x) {
			x.lineNumber -= lineFinder.lineNumber-1;
			Components.utils.reportError(x);
		}
	},

	log: function(msg) {
		Cc["@mozilla.org/consoleservice;1"].getService(Ci.nsIConsoleService).logStringMessage(msg);
	},

	getContents: function(aURL, charset) {
		if( !charset ) {
			charset = "UTF-8"
		}
		var scriptableStream = Cc["@mozilla.org/scriptableinputstream;1"]
			.getService(Ci.nsIScriptableInputStream);
		var unicodeConverter = Cc["@mozilla.org/intl/scriptableunicodeconverter"]
			.createInstance(Ci.nsIScriptableUnicodeConverter);
		unicodeConverter.charset = charset;

		var channel=ioService.newChannelFromURI(aURL);
		var input=channel.open();
		scriptableStream.init(input);
		var str=scriptableStream.read(input.available());
		scriptableStream.close();
		input.close();

		try {
			return unicodeConverter.ConvertToUnicode(str);
		} catch( e ) {
			return str;
		}
	},

	// XPCOM Glue stuff
	QueryInterface: function(iid)
	{
		if (!iid.equals(Ci.nsIObserver) &&
		    !iid.equals(Ci.danbooruIHelperService) &&
		    !iid.equals(Ci.nsISupports) &&
		    !iid.equals(Ci.nsISupportsWeakReference))
			throw Components.results.NS_ERROR_NO_INTERFACE;
		return this;
	},

	get wrappedJSObject() { return this; }
}

// Component registration
var HelperModule = new Object();

HelperModule.registerSelf = function(compMgr, fileSpec, location, type)
{
	var compMgr = compMgr.QueryInterface(Ci.nsIComponentRegistrar);

	if (!this._deferred)
	{
		this._deferred = true;

	// Check if this is built with a bizarro OS_TARGET
	try {
	if (Cc["@mozilla.org/xre/app-info;1"].getService(Ci.nsIXULRuntime).OS == 'linux-gnu')
	{
		//__log("linux-gnu detected");
		// find the extension directory
		var dirs = Cc["@mozilla.org/file/directory_service;1"].getService(Ci.nsIProperties)
				.get("XREExtDL", Ci.nsISimpleEnumerator);
		var dir;
		while(dirs.hasMoreElements())
		{
			dir = dirs.getNext().QueryInterface(Ci.nsILocalFile);
			//__log("checking "+dir.path);
			if(dir.leafName == '{7209145A-6A2A-42C1-99EB-4DE7293990E1}')
				break;
			dir = null;
		}
		// rename the platform component directory
		if (dir)
		{
			//__log("locked on");
			var moveDir;
			dir.append('platform');
			moveDir = dir.clone();
			moveDir.append('Linux_x86-gcc3');
			//__log("using "+moveDir.path+(moveDir.exists?" (exists)":" (doesn't exist)"));
			if(moveDir.exists())
			{
				moveDir.moveTo(dir, 'linux-gnu_x86-gcc3');
				// moveDir will still point to the old path, so we need to use dir
				dir.append('linux-gnu_x86-gcc3');
				dir.append('components');
				__log("danbooruUpHelper: registering "+dir.path);
				compMgr.autoRegister(dir);
			}
		}
	}
	} catch(ex) {
		__log("danbooruUphelper: exception caught during OS_TARGET fix:\n"+ex);
	}

		throw Components.results.NS_ERROR_FACTORY_REGISTER_AGAIN;
	}

	compMgr.registerFactoryLocation(DANBOORUUPHELPER_CID,
			"Danbooru Helper Service",
			DANBOORUUPHELPER_CONTRACTID,
			fileSpec,
			location,
			type);

	var catMgr = Cc["@mozilla.org/categorymanager;1"].getService(Ci.nsICategoryManager);

	catMgr.addCategoryEntry("app-startup",
			DANBOORUUPHELPER_CLASSNAME,
			"service,"+DANBOORUUPHELPER_CONTRACTID,
			true,
			true);

}

HelperModule.unregisterSelf = function(aCompMgr, aLocation, aType) {
	aCompMgr.QueryInterface(Ci.nsIComponentRegistrar);
	aCompMgr.unregisterFactoryLocation(CID, aLocation);

	var catMan = Cc["@mozilla.org/categorymanager;1"].
		getService(Ci.nsICategoryManager);
	catMan.deleteCategoryEntry( "app-startup", "service," + DANBOORUUPHELPER_CONTRACTID, true);
}

HelperModule.getClassObject = function(compMgr, cid, iid)
{
	if (!cid.equals(DANBOORUUPHELPER_CID))
		throw Components.results.NS_ERROR_NO_INTERFACE;
	if (!iid.equals(Ci.nsIFactory))
		throw Components.results.NS_ERROR_NOT_IMPLEMENTED;
	return HelperFactory;
}

HelperModule.canUnload = function(compMgr)
{
	return true;
}

// Returns the singleton object when needed.
var HelperFactory = new Object();

HelperFactory.createInstance = function(outer, iid)
{
	if (outer != null)
		throw Components.results.NS_ERROR_NO_AGGREGATION;
	return danbooruUpHelperObject;
}

// XPCOM Registration Function -- called by Firefox
function NSGetModule(compMgr, fileSpec)
{
	return HelperModule;
}

