package db;
import sugoi.form.ListData.FormData;
import sys.db.Object;
import sys.db.Types;

enum CatalogFlags {
	UsersCanOrder;  		//adhérents peuvent saisir eux meme la commande en ligne
	StockManagement; 		//gestion des commandes
	PercentageOnOrders;		//calcul d'une commission supplémentaire 
}

class Catalog extends Object
{
	public var id : SId;
	public var name : SString<64>;
	
	//responsable
	@formPopulate("populate") @:relation(userId) public var contact : SNull<User>;
	@formPopulate("populateVendor") @:relation(vendorId) public var vendor : Vendor;
	
	public var startDate:SDate;
	public var endDate :SDate;
	
	public var description:SNull<SText>;
	
	@:hideInForms @:relation(groupId) public var group:db.Group;
	public var distributorNum:STinyInt;
	public var flags : SFlags<CatalogFlags>;
	
	public var percentageValue : SNull<SFloat>; 		//fees percentage
	public var percentageName : SNull<SString<64>>;		//fee name
	
	public var type : SInt;

	@:skip inline public static var TYPE_CONSTORDERS = 0; 	//CSA catalog 
	@:skip inline public static var TYPE_VARORDER = 1;		//variable orders catalog
	@:skip var cache_hasActiveDistribs : Bool;
	
	public function new() 
	{
		super();
		flags = cast 0;
		distributorNum = 0;		
		flags.set(UsersCanOrder);
	
	}
	
	/**
	 * The products can be ordered currently ?
	 * 
	 * @deprecated it depends on distributions
	 */
	public function isUserOrderAvailable():Bool {
		
		if (type == TYPE_CONSTORDERS ) {
			return isVisibleInShop();
		}else {
		
			//if ( cache_hasActiveDistribs != null ) return cache_hasActiveDistribs;
			
			//for varying orders, we need to know if there are some available deliveries
			var n = Date.now();			
			var d = db.Distribution.manager.count( $orderStartDate <= n && $orderEndDate >= n && $catalogId==this.id);
			
			//tmp : add the "old" deliveries which have a null orderStartDate
			//d += db.Distribution.manager.count( $orderStartDate == null && $date > n  && $catalogId == this.id );
			
			//cache_hasActiveDistribs = d > 0;
			//return cache_hasActiveDistribs && isVisibleInShop();
			return d>0 && isVisibleInShop();
		}
		
	}
	
	/**
	 * The products can be displayed in a shop ?
	 */
	public function isVisibleInShop():Bool {
		
		//yes if the contract is active and the 'UsersCanOrder' flag is checked
		var n = Date.now().getTime();
		return flags.has(UsersCanOrder) && n < this.endDate.getTime() && n > this.startDate.getTime();
	}

	public function isActive():Bool{
		var n = Date.now().getTime();
		return n < this.endDate.getTime() && n > this.startDate.getTime();
	}
	
	/**
	 * is currently open to orders
	 */
	public function hasRunningOrders(){
		var now = Date.now();
		var n = now.getTime();
		
		var contractOpen = flags.has(UsersCanOrder) && n < this.endDate.getTime() && n > this.startDate.getTime();
		var d = db.Distribution.manager.count( $orderStartDate <= now && $orderEndDate > now && $catalogId==this.id);
		
		return contractOpen && d > 0;
	}
	
	
	public function hasPercentageOnOrders():Bool {
		return flags.has(PercentageOnOrders) && percentageValue!=null && percentageValue!=0;
	}
	
	public function hasStockManagement():Bool {
		return flags.has(StockManagement);
	}
	
	/**
	 * computes a 'percentage' fee or a 'margin' fee 
	 * depending on the group settings
	 * 
	 * @param	basePrice
	 */
	public function computeFees(basePrice:Float) {
		if (!hasPercentageOnOrders()) return 0.0;
		
		if (group.flags.has(ComputeMargin)) {
			//commercial margin
			return (basePrice / ((100 - percentageValue) / 100)) - basePrice;
			
		}else {
			//add a percentage
			return percentageValue / 100 * basePrice;
		}
	}
	
	/**
	 * 
	 * @param	amap
	 * @param	large = false	Si true, montre les contrats terminés depuis moins d'un mois
	 * @param	lock = false
	 */
	public static function getActiveContracts(amap:db.Group,?large = false, ?lock = false) {
		var now = Date.now();
		var end = Date.now();
	
		if (large) {
			end = DateTools.delta(end , -1000.0 * 60 * 60 * 24 * 30);
			return db.Catalog.manager.search($group == amap && $endDate > end,{orderBy:-vendorId}, lock);	
		}else {
			return db.Catalog.manager.search($group == amap && $endDate > now && $startDate < now,{orderBy:-vendorId}, lock);	
		}
	}
	
	/**
	 * get products in this contract
	 * @param	onlyActive = true
	 * @return
	 */
	public function getProducts(?onlyActive = true):List<Product> {
		if (onlyActive) {
			return Product.manager.search($catalog==this && $active==true,{orderBy:name},false);	
		}else {
			return Product.manager.search($catalog==this,{orderBy:name},false);	
		}
	}
	
	/**
	 * get a few products to display
	 * @param	limit = 6
	 */
	public function getProductsPreview(?limit = 6){
		return Product.manager.search($catalog==this && $active==true,{limit:limit,orderBy:-id},false);	
	}
	
		
	/**
	 *  get users who have orders in this contract ( including user2 )
	 *  @return Array<db.User>
	 */
	public function getUsers():Array<db.User> {
		var pids = getProducts().map(function(x) return x.id);
		var ucs = db.UserOrder.manager.search($productId in pids, false);
		var ucs2 = [];
		for( uc in ucs) {
			ucs2.push(uc.user);
			if(uc.user2!=null) ucs2.push(uc.user2);
		}
		
		//comme un user peut avoir plusieurs produits au sein d'un contrat, il faut dédupliquer cette liste
		var out = new Map<Int,db.User>();
		for (u in ucs2) {
			out.set(u.id, u);
		}
		
		return Lambda.array(out);
	}
	
	/**
	 * Get all orders of this contract
	 * @param	d	A delivery is needed for varying orders contract
	 * @return
	 */
	public function getOrders(?d:db.Distribution):Array<db.UserOrder> {
		if (type == TYPE_VARORDER && d == null) throw "This type of contract must have a delivery";
		
		//get product ids, some of the products may have been disabled but we keep the order
		var pids = getProducts(false).map(function(x) return x.id);
		var ucs = new List<db.UserOrder>();
		if (type == TYPE_VARORDER) {
			ucs = db.UserOrder.manager.search( ($productId in pids) && $distribution==d,{orderBy:userId}, false);	
		}else {
			ucs = db.UserOrder.manager.search( ($productId in pids) ,{orderBy:userId}, false);	
		}		
		return Lambda.array(ucs);
	}

	/**
	 * Get orders for a user.
	 *
	 * @param	d
	 * @return
	 */
	public function getUserOrders(u:db.User,?d:db.Distribution,?includeUser2=true):Array<db.UserOrder> {
		if (type == TYPE_VARORDER && d == null) throw "This type of contract must have a delivery";

		var pids = getProducts(false).map(function(x) return x.id);
		var ucs = new List<db.UserOrder>();
		if (d != null && d.catalog.type==db.Catalog.TYPE_VARORDER) {
			if(includeUser2){
				ucs = db.UserOrder.manager.search( ($productId in pids) && $distribution==d && ($user==u || $user2==u ), false);
			}else{
				ucs = db.UserOrder.manager.search( ($productId in pids) && $distribution==d && ($user==u), false);
			}
		}else{
			if(includeUser2){
				ucs = db.UserOrder.manager.search( ($productId in pids) && ($user==u || $user2==u ),false);
			}else{
				ucs = db.UserOrder.manager.search( ($productId in pids) && ($user==u),false);
			}
			
		}
		return Lambda.array(ucs);
	}

	public function getDistribs(excludeOld = true,?limit=999):List<Distribution> {
		if (excludeOld) {
			//still include deliveries which just expired in last 24h
			return Distribution.manager.search($end > DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24) && $catalog == this, { orderBy:date,limit:limit } );
		}else{
			return Distribution.manager.search( $catalog == this, { orderBy:date,limit:limit } );
		}
	}

	public function getVisibleDocuments( user : db.User ) : List<sugoi.db.EntityFile> {

		var isSubscribedToCatalog = false;
		if ( user != null && this.type == db.Catalog.TYPE_CONSTORDERS ) { //Amap catalog

			var userCatalogs : Array<db.Catalog> = user.getContracts(this.group);
			isSubscribedToCatalog = Lambda.exists( userCatalogs, function( usercatalog ) return usercatalog.id == this.id ); 
		}

		if ( isSubscribedToCatalog ) {

			return sugoi.db.EntityFile.manager.search( $entityType == 'catalog' && $entityId == this.id && $documentType == 'document', false);
		}

		if ( user != null && user.isMemberOf(group) ) {

			return sugoi.db.EntityFile.manager.search( $entityType == 'catalog' && $entityId == this.id && $documentType == 'document' && $data != 'subscribers', false);
		}
		
		
		return sugoi.db.EntityFile.manager.search( $entityType == 'catalog' && $entityId == this.id && $documentType == 'document' && $data == 'public', false);

	}
	
	override function toString() {
		return name+" du "+this.startDate.toString().substr(0,10)+" au "+this.endDate.toString().substr(0,10);
	}
	
	public function populate() {
		return App.current.user.getGroup().getMembersFormElementData();
	}
	
	/**
	 * get a vendor list as form data
	 * @return
	 */
	public function populateVendor():FormData<Int>{
		if(this.group==null) return [];
		var vendors = this.group.getVendors();
		var out = [];
		for (v in vendors) {
			out.push({label:v.name, value:v.id });
		}
		return out;
	}
	
	public static function getLabels(){
		var t = sugoi.i18n.Locale.texts;
		return [
			"name" 				=> t._("Catalog name"),
			"startDate" 		=> t._("Start date"),
			"endDate" 			=> t._("End date"),
			"description" 		=> t._("Description"),
			"distributorNum" 	=> t._("Number of required volunteers during a distribution"),
			"flags" 			=> t._("Options"),
			"percentageValue" 	=> t._("Fees percentage"),
			"percentageName" 	=> t._("Fees label"),			
			"contact" 			=> t._("Contact"),			
			"vendor" 			=> t._("Farmer"),			
		];
	}
	
	
}