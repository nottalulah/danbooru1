/* ***** BEGIN LICENSE BLOCK *****
 * Version: MPL 1.1/GPL 2.0/LGPL 2.1
 *
 * The contents of this file are subject to the Mozilla Public License Version
 * 1.1 (the "License"); you may not use this file except in compliance with
 * the License. You may obtain a copy of the License at
 * http://www.mozilla.org/MPL/
 *
 * Software distributed under the License is distributed on an "AS IS" basis,
 * WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License
 * for the specific language governing rights and limitations under the
 * License.
 *
 * The Original Code is Mozilla Communicator client code.
 *
 * The Initial Developer of the Original Code is
 * Netscape Communications Corporation.
 * Portions created by the Initial Developer are Copyright (C) 1998
 * the Initial Developer. All Rights Reserved.
 *
 * Contributor(s):
 *   Joe Hewitt <hewitt@netscape.com> (Original Author)
 *
 * Alternatively, the contents of this file may be used under the terms of
 * either the GNU General Public License Version 2 or later (the "GPL"), or
 * the GNU Lesser General Public License Version 2.1 or later (the "LGPL"),
 * in which case the provisions of the GPL or the LGPL are applicable instead
 * of those above. If you wish to allow use of your version of this file only
 * under the terms of either the GPL or the LGPL, and not to allow others to
 * use your version of this file under the terms of the MPL, indicate your
 * decision by deleting the provisions above and replace them with the notice
 * and other provisions required by the GPL or the LGPL. If you do not delete
 * the provisions above, a recipient may use your version of this file under
 * the terms of any one of the MPL, the GPL or the LGPL.
 *
 * ***** END LICENSE BLOCK ***** */

#ifndef __danbooruTagHistoryService__
#define __danbooruTagHistoryService__

#include "nsStringAPI.h"

#include "danbooruITagHistoryService.h"
#include "danbooruIAutoCompleteArrayResult.h"
#include "nsIXMLHttpRequest.h"
#include "nsIDOMEventListener.h"
#include "nsCOMPtr.h"
#include "nsIObserver.h"
#include "nsIDOMEventListener.h"
#include "nsIXMLHttpRequest.h"
#include "nsIPrefBranch.h"
#include "nsWeakReference.h"
#include "mozIStorageConnection.h"
#include "mozIStorageStatement.h"

class nsIXMLHttpRequest;

#define DANBOORU_TAGHISTORYSERVICE_CID \
{ 0xa6c3c34, 0x6560, 0x4000, { 0xb7, 0xe, 0x7f, 0xc8, 0x9d, 0x6b, 0xc1, 0x48 } }
#define DANBOORU_TAGHISTORYSERVICE_CONTRACTID "@unbuffered.info/danbooru/taghistory-service;1"

class danbooruTagHistoryService : public danbooruITagHistoryService,
                      public nsIObserver,
                      public nsIDOMEventListener,
//                      public nsIFormSubmitObserver,
                      public nsSupportsWeakReference
{
public:
  NS_DECL_ISUPPORTS
  NS_DECL_DANBOORUITAGHISTORYSERVICE
  NS_DECL_NSIOBSERVER
  NS_DECL_NSIDOMEVENTLISTENER

  // nsIFormSubmitObserver
  //NS_IMETHOD Notify(nsIContent* formNode, nsIDOMWindowInternal* window, nsIURI* actionURL, PRBool* cancelSubmit);

  // nsIDOMEventListener
  //NS_IMETHOD HandleEvent(nsIDOMEvent* aEvent);

  danbooruTagHistoryService();
  virtual ~danbooruTagHistoryService();
  nsresult Init();

  static danbooruTagHistoryService *GetInstance();

protected:
  // Database I/O
  nsresult OpenDatabase();
  nsresult CloseDatabase();
  void ReportDBError();

  // mozStorage
  nsCOMPtr<mozIStorageConnection> mDB;

  nsCOMPtr<mozIStorageStatement> mInsertStmt;
  nsCOMPtr<mozIStorageStatement> mUpdateTypeStmt;
  nsCOMPtr<mozIStorageStatement> mRemoveByIDStmt;
  nsCOMPtr<mozIStorageStatement> mIncrementStmt;
  nsCOMPtr<mozIStorageStatement> mSearchStmt;
  nsCOMPtr<mozIStorageStatement> mExistsStmt;
  nsCOMPtr<mozIStorageStatement> mMaxIDStmt;
  nsCOMPtr<mozIStorageStatement> mRowCountStmt;

  // XML processing
  nsresult ProcessTagXML(void *, PRBool);

  static PRBool TagHistoryEnabled();

  static danbooruTagHistoryService *gTagHistory;

  static PRBool gTagHistoryEnabled;
  static PRBool gPrefsInitialized;

  nsCOMPtr<nsIXMLHttpRequest> mRequest;
  // no way to get XHR to send this along with the load event, but there's only one request at a time per XHR anyway
  PRBool mInserting;

  nsCOMPtr<nsIPrefBranch> mPrefBranch;

};

#endif // __danbooruTagHistoryService__
