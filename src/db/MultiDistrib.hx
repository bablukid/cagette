package db;
import sys.db.Object;
import sys.db.Types;
import Common;
using tools.ObjectListTool;
using Lambda;

/**
 * MultiDistrib represents a global distributions with many vendors. 	
 * @author fbarbut
 */
class MultiDistrib extends Object
{
	public var id : SId;
	@hideInForms @:relation(groupId) public var group : db.Amap;
	public var distribStartDate : SDateTime; 
	public var distribEndDate : SDateTime;	
	public var orderStartDate : SNull<SDateTime>; 
	public var orderEndDate : SNull<SDateTime>;
	@hideInForms @:relation(distributionCycleId) public var distributionCycle : SNull<DistributionCycle>;
	
	@formPopulate("placePopulate")
	@:relation(placeId)
	public var place : Place;

	@hideInForms public var counterBeforeDistrib:SFloat; //counter before distrib "fond de caisse"

	@:skip public var contracts : Array<db.Contract>;
	@:skip public var extraHtml : String;
	
	@hideInForms public var volunteerRolesIds : SNull<String>;

	public function new(){
		super();
		contracts = [];
		extraHtml = "";
	}
	
	public static function get(date:Date, place:db.Place, ?lock=false/*,contractType:Int*/){
		var start = tools.DateTool.setHourMinute(date, 0, 0);
		var end = tools.DateTool.setHourMinute(date, 23, 59);

		return db.MultiDistrib.manager.select($distribStartDate>=start && $distribStartDate<=end && $place==place /*&& $type==contractType*/,lock);
	}

	public static function getFromTimeRange( group: db.Amap, from: Date, to: Date ) : Array<MultiDistrib> {

		var multidistribs = new Array<db.MultiDistrib>();
		var start = tools.DateTool.setHourMinute(from, 0, 0);
		var end = tools.DateTool.setHourMinute(to, 23, 59);
		
		multidistribs = Lambda.array(db.MultiDistrib.manager.search( $group == group && $distribStartDate >= start && $distribStartDate <= end, false ));
		
		//sort by date desc
		multidistribs.sort(function(x,y){
			return Math.round( x.getDate().getTime()/1000 ) - Math.round(y.getDate().getTime()/1000 );
		});

		//trigger event
		for(md in multidistribs) App.current.event(MultiDistribEvent(md));

		return multidistribs;
	}

	/**
	 * TODO : refacto this to use getFromTimeRange();
	 */
	/*public static function getNextMultiDeliveries(group:db.Amap){
		
		var out = new Map < String, {
			place:db.Place, 		//common delivery place
			startDate:Date, 		//global delivery start
			endDate:Date,			//global delivery stop
			orderStartDate:Date, 	//global orders opening date
			orderEndDate:Date,		//global orders closing date
			active:Bool,
			products:Array<ProductInfo>, //available products ( if no order )
			myOrders:Array<{distrib:db.Distribution,orders:Array<UserOrder>}>	//my orders			
		}>();
		
		var n = Date.now();
		var now = new Date(n.getFullYear(), n.getMonth(), n.getDate(), 0, 0, 0);
	
		var contracts = db.Contract.getActiveContracts(group);
		var cids = Lambda.map(contracts, function(p) return p.id);
		
		//var pids = Lambda.map(db.Product.manager.search($contractId in cids,false), function(x) return x.id);
		//var out =  UserContract.manager.search(($userId == id || $userId2 == id) && $productId in pids, lock);	
		
		//available deliveries
		var inSixMonth = DateTools.delta(now, 1000.0 * 60 * 60 * 24 * 30 * 6);
		var distribs = db.Distribution.manager.search(($contractId in cids) && $date >= now && $date <= inSixMonth , { orderBy:date }, false);
		
		for (d in distribs) {			
			
			//we had the distribution key ( place+date ) and the contract type in order to separate constant and varying contracts
			var key = d.getKey() + "|" + d.contract.type;
			var o = out.get(key);
			if (o == null) o = {place:d.place, startDate:d.date, active:null, endDate:d.end, products:[], myOrders:[], orderStartDate:null,orderEndDate:null};
			
			//user orders
			var orders = [];
			if(App.current.user!=null) orders = d.contract.getUserOrders(App.current.user,d);
			if (orders.length > 0){
				o.myOrders.push({distrib:d,orders:service.OrderService.prepare(orders)});
			}else{
				//no "order block" if no shop mode	
				if (!group.hasShopMode() ) {		
					continue;		
				}		

				//if its a constant order contract, skip this delivery		
				if (d.contract.type == db.Contract.TYPE_CONSTORDERS){		
					continue;		
				}
				
				//products preview if no orders
				for ( p in d.contract.getProductsPreview(9)){
					o.products.push( p.infos(null,false) );	
				}	
			}
			
			if (d.contract.type == db.Contract.TYPE_VARORDER){
				
				//old distribs may have an empty orderStartDate
				if (d.orderStartDate == null) {
					continue;
				}
				
				//if order opening is more far than 1 month, skip it
				// if (d.orderStartDate.getTime() > inOneMonth.getTime() ){
				// 	continue;
				// }
				
				//display closest opening date
				if (o.orderStartDate == null){
					o.orderStartDate = d.orderStartDate;
				}else if (o.orderStartDate.getTime() > d.orderStartDate.getTime()){
					o.orderStartDate = d.orderStartDate;
				}
				
				//display most far closing date
				if (o.orderEndDate == null){
					o.orderEndDate = d.orderEndDate;
				}else if (o.orderEndDate.getTime() < d.orderEndDate.getTime()){
					o.orderEndDate = d.orderEndDate;
				}
				
				out.set(key, o);	
				
			}else{
				//in constant orders, add block only if there is an order
				if(o.myOrders.length>0) out.set(key, o);
				
			}
		}
		
		//shuffle and limit product lists		
		for ( o in out){
			o.products = thx.Arrays.shuffle(o.products);			
			o.products = o.products.slice(0, 9);
		}
		
		//decide if active or not
		var now = Date.now();
		for( o in out){
			
			if (o.orderStartDate == null) continue; //constant orders
			
			if (now.getTime() >= o.orderStartDate.getTime()  && now.getTime() <= o.orderEndDate.getTime() ){
				//order currently open
				o.active = true;
				
			}else {
				o.active = false;
				
			}
		}	
		
		return Lambda.array(out);
	}*/

	public function getPlace(){
		return place;
	}

	public function getDate(){
		return distribStartDate;
	}

	public function getEndDate(){
		return distribEndDate;
	}

	public function getProductsExcerpt(productNum:Int):Array<ProductInfo>{
		var key = "productsExcerpt-"+getKey();
		var cache:Array<Int> = sugoi.db.Cache.get(key);
		if(cache!=null){
			var out = [];
			//try{
				for( pid in cache.array()){
					var p = db.Product.manager.get(pid,false);
					if(p!=null) out.push(p.infos());
				}
			//}catch(e:Dynamic){
			// 	sugoi.db.Cache.destroy(key);
			// }
			
			return out;
		}

		var products = [];
		for( d in getDistributions()){
			for ( p in d.contract.getProductsPreview(productNum)){
				products.push( p.infos(null,false) );	
			}
		}
		products = thx.Arrays.shuffle(products);			
		products = products.slice(0, productNum);
		sugoi.db.Cache.set(key, products.map(function(p)return p.id).array(), 3600 );
		return products;	

	}

	public function userHasOrders(user:db.User,type:Int):Bool{
		if(user==null) return false;
		for ( d in getDistributions(type)){
			if(d.hasUserOrders(user)) return true;						
		}
		return false;
	}
	
	/**
	orders currently open ?
	**/
	public function isActive(){

		if (getOrdersStartDate() == null) return false; //constant orders
			
		var now = Date.now();	
		if (now.getTime() >= getOrdersStartDate().getTime()  && now.getTime() <= getOrdersEndDate().getTime() ){			
			return true;				
		}else {
			return false;				
		}
	}

	public function getOrdersStartDate(?includingExceptions=false){
		if(includingExceptions){
			//find earliest order start date 
			var date = orderStartDate;
			for(d in getDistributions(db.Contract.TYPE_VARORDER)){
				if(d.orderStartDate.getTime() < date.getTime()) date = d.orderStartDate;
			}
			return date;
		}else{
			return orderStartDate;
		}
		
	}

	public function getOrdersEndDate(?includingExceptions=false){
		if(includingExceptions){
			//find lates order end date 
			var date = orderEndDate;
			for(d in getDistributions(db.Contract.TYPE_VARORDER)){
				if(d.orderEndDate.getTime() > date.getTime()) date = d.orderEndDate;
			}
			return date;
		}else{
			return orderEndDate;
		}
		
	}

	public function getUserTmpBasket(user:db.User){
		
	}

	/**
		Get distributions for constant orders or variable orders.
	**/
	public function getDistributions(?type:Int){
		if(type==null) return Lambda.array( db.Distribution.manager.search($multiDistrib==this,false) );
		var out = [];
		for ( d in db.Distribution.manager.search($multiDistrib==this,false)){
			if( d.contract.type==type ) out.push(d);
		}
		return out;
	}

	public function getDistributionForContract(contract:db.Contract):db.Distribution{
		for( d in getDistributions()){
			if(d.contract.id == contract.id) return d;
		}
		return null;
	}

	/**
	 * Get all orders involved in this multidistrib
	 */
	public function getOrders(?type:Int){
		var out = [];
		for ( d in getDistributions(type)){
			out = out.concat(d.getOrders().array());
		}
		return out;		
	}

	/**
	 * Get orders for a user in this multidistrib
	 * @param user 
	 */
	public function getUserOrders(user:db.User){
		var out = [];
		for ( d in getDistributions() ){
			var pids = Lambda.map( d.contract.getProducts(false), function(x) return x.id);		
			var userOrders =  db.UserContract.manager.search( $userId == user.id && $distributionId==d.id && $productId in pids , false);	
			for( o in userOrders ){
				out.push(o);
			}
		}
		return out;		
	}

	public function getVendors():Array<db.Vendor>{
		var vendors = new Map<Int,db.Vendor>();
		for( d in getDistributions()) vendors.set(d.contract.vendor.id,d.contract.vendor);
		return Lambda.array(vendors);
	}
	
	public function getUsers(?type:Int){
		var users = [];
		for ( o in getOrders(type)) users.push(o.user);
		return users.deduplicate();		
	}

	public function getState():String{
		var now = Date.now().getTime();
		if(getOrdersStartDate()==null || getOrdersEndDate()==null) return null;
		
		if( getDate().getTime() > now ){
			//we're before distrib

			if( getOrdersStartDate(true).getTime() > now ){
				return "notYetOpen";
			}
			
			if( getOrdersEndDate(true).getTime() > now ){
				return "open";
			}else{
				return "closed";
			}
			

		}else{
			//after distrib
			if(isConfirmed()){
				return "validated";
			}else{
				return "distributed";
			}
		}
	}

	public function getStatus(){
		return getState();
	}
	
	
	public function isConfirmed():Bool{
		//cannot be in future
		if(getDate().getTime()>Date.now().getTime()) return false;
		var distributions = getDistributions(db.Contract.TYPE_VARORDER);
		return Lambda.count( distributions , function(d) return d.validated) == distributions.length;
	}

	public function isValidated(){
		return isConfirmed();
	}
	
	public function checkConfirmed():Bool{
		
		for ( d in getDistributions(db.Contract.TYPE_VARORDER)){
			if(!d.validated){
				var orders = d.getOrders();
				var allOrdersPaid = Lambda.count( orders , function(d) return d.paid) == orders.length;		

				if (allOrdersPaid){
					d.lock();
					d.validated = true;
					d.update();
				}

			}
			
		}
		
		
		return isConfirmed();
	}

	//get key by date-place-type
	public function getKey(){
		return "md"+this.id;
		//return distributions[0].getKey() + "-" + distributions[0].contract.type;
	}

	override public function toString(){
		try{
			return "Multidistrib à "+getPlace().name+" le "+getDate();
		}catch(e:Dynamic){
			return "#"+this.id;
		}
		
	}

	public function placePopulate():sugoi.form.ListData.FormData<Int> {
		var out = [];
		var places = new List();
		if(this.place!=null){			
			places = db.Place.manager.search($amapId == this.place.amap.id, false);
		}
		for (p in places) out.push( { label:p.name,value:p.id} );
		return out;
	}

	public static function getLabels(){
		var t = sugoi.i18n.Locale.texts;
		return [
			"distribStartDate"	=> t._("Date"),
			"distribEndDate"	=> t._("End hour"),
			"place" 			=> t._("Place"),
			"orderStartDate" 	=> t._("Orders opening date"),
			"orderEndDate" 		=> t._("Orders closing date"),
		];
	}

	public function getGroup(){
		return place.amap;
	}

	/**
		TODO : refacto with foreign key with multidistrib
	**/
	public function getBaskets():Array<db.Basket>{
		var baskets = [];
		for( o in getOrders()){
			if(o.basket!=null) baskets.push(o.basket);
		}
		return baskets.deduplicate();
	}

	public function getUserBasket(user:db.User){
		var orders = getUserOrders(user);
		for( o in orders ){
			if(o.basket!=null) return o.basket;
		}
		return null;
	}

	/**
		Get total income of the md, variable and constant
	**/
	public function getTotalIncome():Float{
		var income = 0.0;
		
		for( d in getDistributions()){
			income += d.getTurnOver();
		}

		return income;
	}


	public function getVolunteerRoles() {

		var volunteerRoles: Array<db.VolunteerRole> = [];
		if (this.volunteerRolesIds != null) {

			var multidistribRoleIds = getVolunteerRoleIds();
			volunteerRoles = new Array<db.VolunteerRole>();
			for ( roleId in multidistribRoleIds ) {
				var volunteerRole = db.VolunteerRole.manager.get(roleId);
				if ( volunteerRole != null ) {
					volunteerRoles.push( volunteerRole );
				}
			}

			volunteerRoles.sort(function(b, a) { 
				var a_str = (a.contract == null ? "null" : Std.string(a.contract.id)) + a.name.toLowerCase();
				var b_str = (b.contract == null ? "null" : Std.string(b.contract.id)) + b.name.toLowerCase();
				return  a_str < b_str ? 1 : -1;
			});
		}
		
		return volunteerRoles;
	}

	public function getVolunteerRoleIds():Array<Int>{
		if(volunteerRolesIds==null) return [];
		return volunteerRolesIds.split(",").map(Std.parseInt);
	}

	public function getVolunteers() {
		return Lambda.array(db.Volunteer.manager.search($multiDistrib == this, false));
	}


	public function hasVacantVolunteerRoles() {

		if ( this.volunteerRolesIds != null && canVolunteersJoin() ) {
			var volunteerRoles = this.getVolunteerRoles();
			if ( volunteerRoles != null && volunteerRoles.length > db.Volunteer.manager.count($multiDistrib == this) ) {
				return true;
			} 
		}
		return false;
	}

	public function getVacantVolunteerRoles():Array<db.VolunteerRole> {

		if (hasVacantVolunteerRoles()) {
			var volunteers = getVolunteers();
			var vacantVolunteerRoles = getVolunteerRoles();

			for ( volunteer in volunteers ) {
				vacantVolunteerRoles.remove(volunteer.volunteerRole);
			}
			vacantVolunteerRoles.sort(function(b, a) { return a.name.toLowerCase() < b.name.toLowerCase() ? 1 : -1; });
			return vacantVolunteerRoles;
		}

		return [];
	}

	public function hasVolunteerRole(role: db.VolunteerRole) {
		var volunteerRoles: Array<db.VolunteerRole> = getVolunteerRoles();
		if (volunteerRoles == null) return false;
		return Lambda.has(volunteerRoles, role);
	}

	public function getVolunteerForRole(role: db.VolunteerRole) {
		return db.Volunteer.manager.select($multiDistrib == this && $volunteerRole == role, false);
	}

	public function getVolunteerForUser(user: db.User): Array<db.Volunteer> {
		return Lambda.array(db.Volunteer.manager.search($multiDistrib == this && $user == user, false));
	}
	
	/**
		Can volunteers join ( check on date and daysBeforeDutyPeriodsOpen )
	**/
	public function canVolunteersJoin() {
		var joinDate = DateTools.delta( this.distribStartDate, - 1000.0 * 60 * 60 * 24 * this.group.daysBeforeDutyPeriodsOpen );
		return Date.now().getTime() >= joinDate.getTime();		
	}


}