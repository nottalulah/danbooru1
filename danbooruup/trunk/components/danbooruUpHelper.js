// -*- Mode: javascript; tab-width: 8; indent-tabs-mode: t; javascript-indent-level: 8; -*-
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

let (loader = Cc["@mozilla.org/moz/jssubscript-loader;1"].getService(Ci.mozIJSSubScriptLoader)) {
	loader.loadSubScript("chrome://danbooruup/content/utils.js");
	loader.loadSubScript("chrome://danbooruup/content/uploader.js");
}

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
			break;
		}
	},
	startTimer: function()
	{
		if (this.mTimer)
			this.mTimer.cancel();
		if (!this._branch.getBoolPref("autocomplete.update.ontimer"))
			return;
		this.mTimer = Cc["@mozilla.org/timer;1"].createInstance(Ci.nsITimer);
		this.mTimer.initWithCallback(this, prefBranch.getIntPref("autocomplete.update.interval")*60*1000, this.mTimer.TYPE_REPEATING_SLACK);
	},
	startupUpdate: function()
	{
		if (!this.tagService) return;
		var full = true;
		if (!this._branch.getBoolPref("autocomplete.enabled"))
			return;
		if (!this._branch.getBoolPref("autocomplete.update.onstartup"))
			return;
		if (this._branch.getBoolPref("autocomplete.update.faststartup") &&
			this.tagService.rowCount > 0) {
			full = false;
			this.mMaxID = this.getMaxID();
		}
		this._branch.setIntPref("autocomplete.update.lastupdate", Date.now());
		try { this.update(full, false); }
		catch(e) {
			__log("DanbooruUp startup update failed: "+e);
		}
	},
	notify: function(aTimer)
	{
		if (!this._branch.getBoolPref("autocomplete.enabled"))
			return;
		if (!this._branch.getBoolPref("autocomplete.update.ontimer"))
		{
			aTimer.cancel();
			this.mTimer = null;
			return;
		}
		this.update(false, false);
	},
	update: function(aFull, aInteractive, aListener)
	{
		if (!this.tagService) return Components.results.NS_ERROR_NOT_AVAILABLE;
		if (!this._branch.getIntPref("autocomplete.update.lastupdate") && (this._branch.getIntPref("autocomplete.update.lastupdate") < Date.now() + cMinTagUpdateInterval))
		{
			dump("skipping tag update, " + (Date.now() + cMinTagUpdateInterval - this._branch.getIntPref("autocomplete.update.lastupdate")) + " seconds left\n");
			return;
		}

		var locationURL;
		try {
			locationURL = ioService.newURI(this._branch.getComplexValue("updateuri", Ci.nsISupportsString).data, '', null)
					.QueryInterface(Ci.nsIURL);
		} catch (e) {
			if(aInteractive)
				promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
			else
				return e.result
		}

		locationURL.query = "limit=0";
		if(this.mMaxID>0 && !aFull)
		{
			locationURL.query += "&after_id="+(this.mMaxID+1);
		}
		dump("using " + locationURL.spec + "\n");

		this._updating = true;
		this._interactive = aInteractive;
		try {
			this.tagService.updateTagListFromURI(locationURL.spec, true, aListener);
		} catch (e) {
			if(e.result==Components.results.NS_ERROR_NOT_AVAILABLE)
			{
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.updatebusy'));
				throw e;
			}
			else {
				this._updating = false;
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
				throw e;
			}
		}
		this._updating = false;
		this.mMaxID = this.getMaxID();
		this._branch.setIntPref("autocomplete.update.lastupdate", Date.now());

		if (this._branch.getBoolPref("autocomplete.update.ontimer") && !this.mTimer)
		{
			this.startTimer();
		}
		return Components.results.NS_OK;
	},
	cleanup: function(aInteractive,aListener)
	{
		var locationURL	= ioService.newURI(this._branch.getComplexValue("updateuri", Ci.nsISupportsString).data, '', null)
				.QueryInterface(Ci.nsIURL);
		locationURL.query = "limit=0";
		dump("using " + locationURL.spec + "\n");
		this._updating = true;
		this._interactive = aInteractive;
		try {
			this.tagService.updateTagListFromURI(locationURL.spec, false, aListener);
		} catch (e) {
			if(e.result==Components.results.NS_ERROR_NOT_AVAILABLE)
			{
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.updatebusy'));
			}
			else {
				this._updating = false;
				if(aInteractive)
					promptService.alert(null, danbooruUpMsg.GetStringFromName('danbooruUp.err.title'), danbooruUpMsg.GetStringFromName('danbooruUp.err.exc') + e);
			}
			throw e;
		}
		this._updating = false;
		this.mMaxID = this.getMaxID();
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
			var cookieStr	= cookieJar.getCookieString(aLocation, null);

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

	downloadRelatedTagDB: function(aInteractive,aListener)
	{
		this.tagService.detachRelatedTagDatabase();
		var dirSvc = Cc["@mozilla.org/file/directory_service;1"].getService(Ci.nsIProperties);
		var outFile = dirSvc.get("ProfD", Ci.nsILocalFile).clone().QueryInterface(Ci.nsILocalFile);
		outFile.append("danboorurelated.sqlite");

		var channel = ioService.newChannel(this._branch.getComplexValue("relatedupdateuri", Ci.nsISupportsString).data, null, null)
				.QueryInterface(Components.interfaces.nsIHttpChannel);
		// will raise a harmless WARNING: NS_ENSURE_TRUE(mCachedResponseHead) failed
		channel.loadFlags = channel.INHIBIT_CACHING | channel.LOAD_BYPASS_CACHE;
		if (outFile.exists())
		{
			var modDate = new Date();
			modDate.setTime(outFile.lastModifiedTime);
			//print('lastmod '+modDate.toUTCString());
			channel.setRequestHeader("If-Modified-Since", modDate.toUTCString(), false);
		}

		var fileStream = Cc["@mozilla.org/network/safe-file-output-stream;1"].createInstance(Ci.nsIFileOutputStream)
			.QueryInterface(Ci.nsISafeOutputStream);
		fileStream.init(outFile, 0x02 | 0x08 | 0x20, 0600, 0);

		var outStr = Components.classes["@mozilla.org/network/buffered-output-stream;1"]
			.createInstance(Components.interfaces.nsIBufferedOutputStream)
			.QueryInterface(Components.interfaces.nsIOutputStream);
		outStr.init(fileStream, 65536);

		ctx = {interactive:aInteractive, outStream: outStr, fileStream: fileStream};
		ctx.wrappedJSObject = ctx;

		var converter = Cc["@mozilla.org/streamconv;1?from=gzip&to=uncompressed"]
			.createInstance(Components.interfaces.nsIStreamConverter);
		converter.asyncConvertData("gzip", "uncompressed", aListener, null);

		channel.notificationCallbacks = aListener;
		try {
			channel.asyncOpen(converter, ctx);
		} catch(e) {
		}
	},

	//
	// danbooruSiteAutocompleter
	//
	prototype_ver:'',
	script_src:[],
	script_ins:'',
	files: ["chrome://danbooruup/content/extra/prototype.js", // needs to be first for below
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
			for (let i=0; i<this.files.length; i++) {
				var script = ioService.newURI(this.files[i],null,null)
				this.script_src.push(this.getContents(script));
			}
			this.script_ins = this.getContents(ioService.newURI("chrome://danbooruup/content/extra/ac-insert.js",null,null));
		} catch(x) { Components.utils.reportError(x); }

		var sandbox = new Components.utils.Sandbox('about:blank');
		// fill sandbox with just enough fake values to get the version from the Prototype object
		sandbox.window = {};
		sandbox.document = {
			evaluate:true,
			HTMLElement:true,
			createElement:function (x) new sandbox.Object
		};
		sandbox.navigator = {userAgent:'Gecko'};
		// suppress inevitable error from not being an actual document scope
		try { Components.utils.evalInSandbox(this.script_src[0], sandbox); } catch(ex) {}
		this.prototype_ver = sandbox.Prototype.Version;
	},

	contentLoaded: function (win)
	{
		// only putting the check here is lazy, but works
		if (!this._branch.getBoolPref("autocomplete.enabled"))
			return;
		if (!this._branch.getBoolPref("autocomplete.site.enabled"))
			return;

		var unsafeWin = win.wrappedJSObject;
		var unsafeLoc = new XPCNativeWrapper(unsafeWin, "location").location;
		var href = new XPCNativeWrapper(unsafeLoc, "href").href;
		// to shut up the complaint about the following QI in the case of about:blank and such
		var scheme = ioService.extractScheme(href);
		if (scheme != "http" && scheme != "https")
			return;

		var winUri = ioService.newURI(href, null, null).QueryInterface(Ci.nsIURL);

		// determine injection based on URI and elements
		var sites = this._branch.getComplexValue("postadduri", Ci.nsISupportsString).data.split("`")
		for (let i=0; i<sites.length; i++) {
			try {
				var uri = ioService.newURI(sites[i], null, null);
				if (winUri.prePath != uri.prePath) continue;
				//this.log(winUri.spec+' matched ' + uri.spec);
				if (winUri.filePath.match(/\/post\/(list|view|show|add|upload)(\/|\.html(\?|$)|\?|$)/) ||
					winUri.filePath.match(/\/post(\/index(\.html)?|\/|$)/) ||
					winUri.filePath.match(/\/user(\/edit(\.html)?|\/|$)/) ||
					winUri.filePath.match(/\/tag(\/mass_edit|\/rename|\/edit|_alias|_implication)(\/|$)/)) {
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
		var res = Cc["@unbuffered.info/danbooru/taghistory-service;1"]
			.getService(Ci.danbooruITagHistoryService).searchTags(s, l);
		var wrap = new ResultWrapper(res);
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
		sandbox.prototype_ver = new sandbox.String(this.prototype_ver);
		sandbox.__proto__ = safeWin;
		sandbox.altsearch = this._branch.getBoolPref('autocomplete.altsearch');

		// put useful declarations into style array inside sandbox
		const TAGTYPE_COUNT = 5;
		var rx = new RegExp("\\s*(background(-\\w+)?|border(-\\w+)?|color|font(-\\w+)?|(-moz-)?padding(-\\w+)?|letter-spacing|margin(-\\w+)?|outline(-\\w+)?|text(-\\w+)?)\\s*:.*;","gm");
		var prefs = prefService.getBranch("extensions.danbooruUp.tagtype.");

		Components.utils.evalInSandbox("var style_arr = [];", sandbox);
		for(let i=0, rule; i<TAGTYPE_COUNT; i++) {
			rule = prefs.getCharPref(i).replace(/[{}]/g, '').match(rx).join('').split(';').join(";\n");
			rule = rule.replace(/^\s*-moz[^:]+\s*:[^;]+;/mg, '').replace(/\s{2,}/mg,'');
			Components.utils.evalInSandbox("style_arr['"+ i +"'] = atob('"+ btoa(rule) +"');", sandbox);
			rule = prefs.getCharPref(i+".selected").replace(/[{}]/g, '').match(rx).join('').split(';').join(";\n");
			rule = rule.replace(/^\s*-moz[^:]+\s*:[^;]+;/mg, '').replace(/\s{2,}/mg,'');
			Components.utils.evalInSandbox("style_arr['"+ i +".selected'] = atob('"+ btoa(rule) +"');", sandbox);
		}

		try {
			// load in the source from the content package
			Components.utils.evalInSandbox("var script_arr = [];", sandbox);
			for (let i=0; i<this.script_src.length; i++) {
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

	log: function(msg)
	{
		Cc["@mozilla.org/consoleservice;1"].getService(Ci.nsIConsoleService).logStringMessage(msg);
	},

	getContents: function(aURL, charset)
	{
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
		if (iid.equals(Ci.nsIObserver) ||
		    iid.equals(Ci.danbooruIHelperService) ||
		    iid.equals(Ci.nsISupports) ||
		    iid.equals(Ci.nsISupportsWeakReference) ||
		    iid.equals(Ci.nsIClassInfo))
			return this;
		throw Components.results.NS_ERROR_NO_INTERFACE;
	},

	get wrappedJSObject() { return this; },

	// nsIClassInfo
	classDescription: "Danbooru Helper Service",
	classID: DANBOORUUPHELPER_CID,
	contractID: DANBOORUUPHELPER_CONTRACTID,
	flags: Ci.nsIClassInfo.SINGLETON,
	implementationLanguage: Ci.nsIProgrammingLanguage.JAVASCRIPT,
	getHelperForLanguage: function(lang) { return null; },
	getInterfaces: function getInterfaces(aCount) {
		var array = [Ci.nsIObserver,
			Ci.danbooruIHelperService,
			Ci.nsISupportsWeakReference,
			Ci.nsIClassInfo];
		aCount.value = array.length;
		return array;
	}
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
