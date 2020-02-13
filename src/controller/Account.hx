package controller;
import service.SubscriptionService;
import sugoi.form.Form;
import sugoi.form.elements.StringSelect;
import Common;
using Std;
import plugin.Tutorial;

class Account extends Controller
{

	public function new()
	{
		super();
	}
	
	/**
	 * "my account" page
	 */
	@tpl("account/default.mtt")
	function doDefault() {
		
		//Create the list of links to change the language
		var langs = App.config.get("langs").split(";");
		var langNames = App.config.get("langnames").split(";");
		var i=0;
		var langLinks = "";
		for (lang in langs)
		{
			langLinks += "<li><a href=\"?lang=" + langs[i] + "\">" + langNames[i] + "</a></li>";
			i++;
		}
		view.langLinks = langLinks;
		view.langText = langNames[langs.indexOf(app.session.lang)];

		//change account lang
		if (app.params.exists("lang") && app.user!=null){
			app.user.lock();
			app.user.lang = app.params.get("lang");
			app.user.update();
		}
		
		var ua = db.UserGroup.get(app.user, app.user.getGroup());
		if (ua == null) throw Error("/", t._("You are not a member of this group"));
		
		var varOrders = new Map<String,Array<db.UserOrder>>();
		
		var a = App.current.user.getGroup();		
		var oneMonthAgo = DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24 * 30);
		
		//constant orders
		view.subscriptionsByCatalog = SubscriptionService.getUserActiveSubscriptionsByCatalog(app.user,app.user.getGroup());
		view.subscriptionService = SubscriptionService;
				
		//variable orders, grouped by date
		var contracts = db.Catalog.manager.search($type == db.Catalog.TYPE_VARORDER && $group == a && $endDate > oneMonthAgo, false);
		
		for (c in contracts) {
			var ds = c.getDistribs(false);
			for (d in ds) {
				//store orders in a stringmap like "2015-01-01" => [order1,order2,...]
				var k = d.date.toString().substr(0, 10);
				var orders = app.user.getOrdersFromDistrib(d);
				if (orders.length > 0) {
					if (!varOrders.exists(k)) {
						varOrders.set(k, Lambda.array(orders));
					}else {
						var z = varOrders.get(k).concat(Lambda.array(orders));
						varOrders.set(k, z);
					}	
				}
			}
		}
		
		//final structure
		var varOrders2 = new Array<{date:Date,orders:Array<UserOrder>}>();
		for ( k in varOrders.keys()) {

			var d = new Date(k.split("-")[0].parseInt(), k.split("-")[1].parseInt() - 1, k.split("-")[2].parseInt(), 0, 0, 0);
			var orders = service.OrderService.prepare( Lambda.list(varOrders[k]) );
			
			varOrders2.push({date:d,orders:orders});
		}
		
		//sort by date desc
		varOrders2.sort(function(b, a) {
			return Math.round(a.date.getTime()/1000)-Math.round(b.date.getTime()/1000);
		});
		
		view.varOrders = varOrders2;
		
		
		// tutorials
		if (app.user.isAmapManager()) {
			
			
			//actions
			if (app.params.exists('startTuto') ) {
				
				//start a tuto
				app.user.lock();
				var t = app.params.get('startTuto'); 
				app.user.tutoState = {name:t,step:0};
				app.user.update();
			}
			
		
			//tuto state
			var tutos = new Array<{name:String,completion:Float,key:String}>();
			
			for ( k in Tutorial.all().keys() ) {	
				var t = Tutorial.all().get(k);
				
				var completion = null;
				if (app.user.tutoState!=null && app.user.tutoState.name == k) completion = app.user.tutoState.step / t.steps.length;
				
				tutos.push( { name:t.name, completion:completion , key:k } );
			}
			
			view.tutos = tutos;
		}
		
		//should be able to stop tuto in any case
		if (app.params.exists('stopTuto')) {
			//stopped tuto from a tuto window
			app.user.lock();
			app.user.tutoState = null;
			app.user.update();	
			view.stopTuto = true;
		}
		
		checkToken();
		view.userGroup = ua;
	}
	
	@tpl('form.mtt')
	function doEdit() {
		
		var form = db.User.getForm(app.user);
		
		if (form.isValid()) {
			
			if (app.user.id != form.getValueOf("id")) {
				throw "access forbidden";
			}
			var admin = app.user.isAdmin();
			
			form.toSpod(app.user); 
			
			//check email is valid
			if (!sugoi.form.validators.EmailValidator.check(app.user.email)){
				throw Error("/account/edit", t._("Email ::em:: is invalid", {em:app.user.email}));
			}
			
			if (app.user.email2!=null && !sugoi.form.validators.EmailValidator.check(app.user.email2)){
				throw Error("/account/edit", t._("Email ::em:: is invalid", {em:app.user.email2}));
			}

			//check email is available
			var sameEmail = db.User.getSameEmail(app.user.email,app.user.email2);
			if( sameEmail.length > 0 && sameEmail.first().id!=app.user.id){
				throw Error("/account/edit", t._("This email is already used by another account."));
			}
			
			if (!admin) { app.user.rights.unset(Admin); }

			//Check that the user is at least 18 years old
			if (!service.UserService.isBirthdayValid(app.user.birthDate)) {
				app.user.birthDate = null;
			 }
			
			app.user.update();
			throw Ok('/contract', t._("Your account has been updated"));
		}
		
		view.form = form;
		view.title = t._("Modify my account");
	}
	


	/**
		View a basket in a popup
	**/
	@tpl('account/basket.mtt')
	function doBasket(basket : db.Basket){
		view.basket = basket;
		view.orders = service.OrderService.prepare(basket.getOrders());
		view.print = app.params["print"]!=null;
	}
	
	/**
	 * user payments history
	 */
	@tpl('account/payments.mtt')
	function doPayments(){
		var m = app.user;
		var browse:Int->Int->List<Dynamic>;
		
		//default display
		browse = function(index:Int, limit:Int) {
			return db.Operation.getOperationsWithIndex(m,app.user.getGroup(),index,limit,true);
		}
		
		var count = db.Operation.countOperations(m,app.user.getGroup());
		var rb = new sugoi.tools.ResultsBrowser(count, 10, browse);
		view.rb = rb;
		view.member = m;
		view.balance = db.UserGroup.get(m,app.user.getGroup()).balance;
	}

	
	
	
}