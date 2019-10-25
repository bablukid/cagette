package controller;
import sugoi.db.Cache;
import sugoi.Web;
import sugoi.mail.Mail;
import Common;
using Lambda;
using tools.DateTool;

class Cron extends Controller
{
	var now : Date;

	public function new(){
		super();

		//For testing purposes you can add an arg to build a "fake now"
		this.now = App.current.params.exists("now") ? Date.fromString(App.current.params.get("now")) : Date.now();
	}

	public function doDefault(){}
	
	/**
	 * CLI only en prod
	 */
	function canRun() {
		if (App.current.user != null && App.current.user.isAdmin()){
			return true;
		}else if (App.config.DEBUG) {
			return true;
		}else {
			
			if (Web.isModNeko) {
				Sys.print("only CLI.");
				return false;
			}else {
				return true;
			}
		}
	}
	
	public function doMinute() {
		if (!canRun()) return;
		
		app.event(MinutelyCron(this.now));

		//managing buffered emails
		for( i in 0...5){
			var task = new sugoi.tools.TransactionWrappedTask(sendEmailsfromBuffer.bind(i*10));
			task.execute(!App.config.DEBUG);
		}
		
		//warns admin about emails that cannot be sent
		var task = new sugoi.tools.TransactionWrappedTask(function(){
			for( e in sugoi.db.BufferedMail.manager.search($tries>20,{limit:50,orderBy:-cdate},true)  ){
				if(e.sender.email != App.config.get("default_email")){
					var str = t._("Sorry, the email entitled <b>::title::</b> could not be sent.",{title:e.title});
					App.quickMail(e.sender.email,t._("Email not sent"),str);
				} 
				e.delete();
			}
		});
		task.execute(!App.config.DEBUG);

		//Delete old emails
		var task = new sugoi.tools.TransactionWrappedTask(function(){
			var threeMonthsAgo = DateTools.delta(Date.now(), -1000.0*60*60*24*30*3);
			sugoi.db.BufferedMail.manager.delete($cdate < threeMonthsAgo);
		});
		task.execute(!App.config.DEBUG);
	}
	
	/**
	 *  Hourly Cron
	 *  
	 *  this function can be locally tested with `neko index.n cron/hour > cron.log`				
	 */
	public function doHour() {
		
		app.event(HourlyCron(this.now));
		
		//instructions for dutyperiod volunteers
		var task = new sugoi.tools.TransactionWrappedTask(function() {
			//Let's get all the multidistribs that start in the right time range
			var fromNow = now.setHourMinute( now.getHours(), 0 );
			var toNow = now.setHourMinute( now.getHours() + 1, 0);
			var multidistribs: Array<db.MultiDistrib> = Lambda.array( db.MultiDistrib.manager.unsafeObjects(
				'SELECT distrib.* 
				FROM MultiDistrib distrib INNER JOIN `Group` group
				ON distrib.groupId = group.id
				WHERE distrib.distribStartDate >= DATE_ADD(\'${fromNow}\', INTERVAL group.volunteersMailDaysBeforeDutyPeriod DAY)
				AND distrib.distribStartDate < DATE_ADD(\'${toNow}\', INTERVAL group.volunteersMailDaysBeforeDutyPeriod DAY);', false));
			printTitle("Volunteers instruction mail");
			
			for (multidistrib  in multidistribs) {

				var volunteers: Array<db.Volunteer> = multidistrib.getVolunteers();
				if ( volunteers.length != 0 ) {
					print(multidistrib.getGroup().name+" : "+multidistrib.getDate());
					var mail = new Mail();
					mail.setSender(App.config.get("default_email"),"Cagette.net");
					var volunteersList = "<ul>";
					for ( volunteer in  volunteers ) {
						
						mail.addRecipient( volunteer.user.email, volunteer.user.getName() );
						if ( volunteer.user.email2 != null ) {
							mail.addRecipient( volunteer.user.email2 );
						}
						volunteersList += "<li>"+volunteer.volunteerRole.name + " : " + volunteer.user.getCoupleName() + "</li>";
					}
					volunteersList += "</ul>";
					
					mail.setSubject( "["+multidistrib.group.name+"] "+ t._("Instructions for the volunteers of the ::date:: distribution",{date : view.hDate(multidistrib.distribStartDate)}) );
					
					//Let's replace all the tokens
					var ddate = t._("::date:: from ::startHour:: to ::endHour::",{date:view.dDate(multidistrib.distribStartDate),startHour:view.hHour(multidistrib.distribStartDate),endHour:view.hHour(multidistrib.distribEndDate)});
					var emailBody = StringTools.replace( multidistrib.group.volunteersMailContent, "[DATE_DISTRIBUTION]", ddate );
					emailBody = StringTools.replace( emailBody, "[LIEU_DISTRIBUTION]", multidistrib.place.name ); 
					emailBody = StringTools.replace( emailBody, "[LISTE_BENEVOLES]", volunteersList ); 
					mail.setHtmlBody( app.processTemplate("mail/message.mtt", { text: emailBody, group: multidistrib.group  } ) );
					App.sendMail(mail);
				}
			}			
		});
		task.execute(!App.config.DEBUG);


		var taskVolunteersAlert = new sugoi.tools.TransactionWrappedTask(function() {

			//Let's get all the multidistribs that start in the right time range
			var fromNow = now.setHourMinute( now.getHours(), 0 );
			var toNow = now.setHourMinute( now.getHours() + 1, 0);
			var multidistribs: Array<db.MultiDistrib> = Lambda.array( db.MultiDistrib.manager.unsafeObjects(
				'SELECT distrib.* 
				FROM MultiDistrib distrib INNER JOIN `Group` group
				ON distrib.groupId = group.id
				WHERE distrib.distribStartDate >= DATE_ADD(\'${fromNow}\', INTERVAL group.vacantVolunteerRolesMailDaysBeforeDutyPeriod DAY)
				AND distrib.distribStartDate < DATE_ADD(\'${toNow}\', INTERVAL group.vacantVolunteerRolesMailDaysBeforeDutyPeriod DAY);', false));

			var vacantVolunteerRolesMultidistribs = Lambda.filter( multidistribs, function(multidistrib) return multidistrib.hasVacantVolunteerRoles() );
			printTitle("Volunteers alerts");
			for (multidistrib  in vacantVolunteerRolesMultidistribs) {
				print(multidistrib.getGroup().name+" : "+multidistrib.getDate());
				var mail = new Mail();
				mail.setSender(App.config.get("default_email"),"Cagette.net");
				for ( member in multidistrib.group.getMembers() ) {
					mail.addRecipient( member.email, member.getName() );
					if ( member.email2 != null ) {
						mail.addRecipient( member.email2 );
					}
				}

				//vacant roles
				var vacantVolunteerRolesList = "<ul>"+Lambda.map( multidistrib.getVacantVolunteerRoles(),function (r) return "<li>"+r.name+"</li>").join("\n")+"</ul>";
				mail.setSubject( t._("[::group::] We need more volunteers for ::date:: distribution",{group : multidistrib.group.name, date : view.hDate(multidistrib.distribStartDate)}) );
				
				//Let's replace all the tokens
				var ddate = t._("::date:: from ::startHour:: to ::endHour::",{date:view.dDate(multidistrib.distribStartDate),startHour:view.hHour(multidistrib.distribStartDate),endHour:view.hHour(multidistrib.distribEndDate)});
				var emailBody = StringTools.replace( multidistrib.group.alertMailContent, "[DATE_DISTRIBUTION]", ddate );
				emailBody = StringTools.replace( emailBody, "[LIEU_DISTRIBUTION]", multidistrib.place.name ); 
				emailBody = StringTools.replace( emailBody, "[ROLES_MANQUANTS]", vacantVolunteerRolesList ); 										
				mail.setHtmlBody( app.processTemplate("mail/message.mtt", { text: emailBody, group: multidistrib.getGroup()  } ) );

				App.sendMail(mail);
			}			
		});
		taskVolunteersAlert.execute(!App.config.DEBUG);

		//Distrib notifications
		var task = new sugoi.tools.TransactionWrappedTask(function(){
			distribNotif(4,db.User.UserFlags.HasEmailNotif4h); //4h before
			distribNotif(24,db.User.UserFlags.HasEmailNotif24h); //24h before
			distribNotif(0, db.User.UserFlags.HasEmailNotifOuverture); //on command open
		});
		task.execute(true);

		//Distrib Validation notifications				
		var task = new sugoi.tools.TransactionWrappedTask(distribValidationNotif);
		task.execute(true);

		//sendOrdersByProductWhenOrdersClose();
	}
	
	/**
		Daily cron job
	**/
	public function doDaily() {
		if (!canRun()) return;
		
		app.event(DailyCron(this.now));
		
		//ERRORS MONITORING
		var n = Date.now();
		var yest24h = new Date(n.getFullYear(), n.getMonth(), n.getDate(), 0, 0, 0);
		var yest0h = DateTools.delta(yest24h, -1000 * 60 * 60 * 24);
		
		var errors = sugoi.db.Error.manager.search( $date < yest24h && $date > yest0h  );		
		if (errors.length > 0) {
			var report = new StringBuf();
			report.add("<h1>" + App.config.NAME + " : ERRORS</h1>");
			for (e in errors) {
				report.add("<div><pre>"+e.error + " at URL " + e.url + " ( user : " + (e.user!=null?e.user.toString():"none") + ", IP : " + e.ip + ")</pre></div><hr/>");
			}
			
			var m = new Mail();
			m.setSender(App.config.get("default_email"),"Cagette.net");
			m.addRecipient(App.config.get("webmaster_email"));
			m.setSubject(App.config.NAME+" Errors");
			m.setHtmlBody( app.processTemplate("mail/message.mtt", { text:report.toString() } ) );
			App.sendMail(m);
		}
		
		//Demo contracts : deletion after 7 days
		var sevenDaysAgo = DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24 * 7);
		var heightDaysAgo = DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24 * 8);
		for( g in db.Group.manager.search($cdate<sevenDaysAgo && $cdate>heightDaysAgo) ){
			g.deleteDemoContracts();
		}		
		
		//Old Messages cleaning
		db.Message.manager.delete($date < DateTools.delta(Date.now(), -1000.0 * 60 * 60 * 24 * 30 * 6));
		
		//old sessions cleaning
		sugoi.db.Session.clean();
		
		
	}
	
	/**
	 * Send email notifications to users before a distribution
	 * @param	hour
	 * @param	flag
	 */
	function distribNotif(hour:Int, flag:db.User.UserFlags) {
		
		//trouve les distrib qui commencent dans le nombre d'heures demandé
 		//on recherche celles qui commencent jusqu'à une heure avant pour ne pas en rater 
 		var from = DateTools.delta(Date.now(), 1000.0 * 60 * 60 * (hour-1));
 		var to = DateTools.delta(Date.now(), 1000.0 * 60 * 60 * hour);
		
		//if (App.config.DEBUG) from = DateTools.delta(from, 1000.0 * 60 * 60 * 24 * -30);
		
		// dans le cas HasEmailNotifOuverture la date à prendre est le orderStartDate
		// et non pas date qui est la date de la distribution
		var distribs;
		if ( db.User.UserFlags.HasEmailNotifOuverture == flag )
			distribs = db.Distribution.manager.search( $orderStartDate >= from && $orderStartDate <= to , false);
		else
			distribs = db.Distribution.manager.search( $date >= from && $date <= to , false);
		
		//Sys.print("distribNotif "+hour+" from "+from+" to "+to+"<br/>\n");
		
		//on s'arrete immédiatement si aucune distibution trouvée
 		if (distribs.length == 0) return;
		
		//cherche plus tard si on a pas une "grappe" de distrib
		/*while (true) {
			var extraDistribs ;
			if ( db.User.UserFlags.HasEmailNotifOuverture != flag )
				extraDistribs = db.Distribution.manager.search( $date >= to && $date <DateTools.delta(to,1000.0*60*60) , false);	
			else	
				extraDistribs = db.Distribution.manager.search( $orderStartDate >= to && $orderStartDate <DateTools.delta(to,1000.0*60*60) , false);
			for ( e in extraDistribs) distribs.add(e);
			if (extraDistribs.length > 0) {
				//on fait un tour de plus avec une heure plus tard
				to = DateTools.delta(h, 1000.0 * 60 * 60);
			}else {
				//plus de distribs
				break;
			}
		}*/
		
		//on vérifie dans le cache du jour que ces distrib n'ont pas deja été traitées lors d'un cron précédent
		var cacheId = Date.now().toString().substr(0, 10)+Std.string(flag);
		var dist :Array<Int> = sugoi.db.Cache.get(cacheId);
		if (dist != null) {
			for (d in Lambda.array(distribs)) {
				if (Lambda.exists(dist, function(x) return x == d.id)) {
					// Comment this line in case of local test
					distribs.remove(d);
				}
			}
		}else {
			dist = [];
		}
		
		//toutes les distribs trouvées ont deja été traitées
		if (distribs.length == 0) return;
		
		//stocke cache
		for (d in distribs) dist.push(d.id);
		Cache.set(cacheId, dist, 24 * 60 * 60);
		
		//We have now the distribs we want to notify about.
		var distribsByContractId = new Map<Int,db.Distribution>();
		for (d in distribs) {			
			if (d == null || d.catalog==null) continue;
			distribsByContractId.set(d.catalog.id, d);
		}

		//Boucle sur les distributions pour gerer le cas de plusieurs distributions le même jour sur le même contrat
 		var orders = [];
 		for (d in distribs) {
			if (d == null || d.catalog==null) continue;
 			//get orders for both type of contracts
			for ( x in d.catalog.getOrders(d)) orders.push(x);
		}
		
		/*
		 * Group orders by users-group to receive separate emails by groups for the same user.
		 * Map key is $userId-$groupId
		*/
		var users = new Map <String,{
			user:db.User,
			distrib:db.Distribution,
			products:Array<db.UserOrder>,
			vendors:Array<db.Vendor>		
		}>();
		
		for (o in orders) {
			
			var x = users.get(o.user.id+"-"+o.product.catalog.group.id);
			if (x == null) x = {user:o.user,distrib:null,products:[],vendors:[]};
			x.distrib = distribsByContractId.get(o.product.catalog.id);
			x.products.push(o);			
			users.set(o.user.id+"-"+o.product.catalog.group.id, x);
			//trace (o.userId+"-"+o.product.catalog.amap.id, x);Sys.print("<br/>\n");
			 
			// Prévenir également le deuxième user en cas des commandes alternées
 			if (o.user2 != null) {
 				var x = users.get(o.user2.id+"-"+o.product.catalog.group.id);
 				if (x == null) x = {user:o.user2,distrib:null,products:[],vendors:[]};
 				x.distrib = distribsByContractId.get(o.product.catalog.id);
 				x.products.push(o);
 				users.set(o.user2.id+"-"+o.product.catalog.group.id, x);
 				//trace (o.user2.id+"-"+o.product.catalog.amap.id, x);Sys.print("<br/>\n");
 			}
		}

		//remove zero qt orders
		for( k in users.keys()){
			var x = users.get(k);
			var total = 0.0;
			for( o in x.products) total += o.quantity;
			if(total==0.0) users.remove(k);
		}
		
		// Dans le cas de l'ouverture de commande, ce sont tous les users qu'il faut intégrer
		if ( db.User.UserFlags.HasEmailNotifOuverture == flag )
		{
 			for (d in distribs) {
				var memberList = d.catalog.group.getMembers();
				for (u in memberList) {
					var x = users.get(u.id+"-"+d.catalog.group.id);
					if (x == null) x = {user:u,distrib:null,products:[],vendors:[]};
					x.distrib = distribsByContractId.get(d.catalog.id);
					x.vendors.push(d.catalog.vendor);
					users.set(u.id+"-"+d.catalog.group.id, x);
					//print(u.id+"-"+d.catalog.amap.id, x);
				}
			}
		}

		for ( u in users) {
			
			if (u.user.flags.has(flag) ) {
				
				if (u.user.email != null) {
					var group = u.distrib.catalog.group;
					this.t = sugoi.i18n.Locale.init(u.user.lang); //switch to the user language

					var text;
					if ( db.User.UserFlags.HasEmailNotifOuverture == flag ) 
					{
						//order opening notif
						text = t._("Opening of orders for the delivery of <b>::date::</b>", {date:view.hDate(u.distrib.date)});
						text += "<br/>";
						text += t._("The following suppliers are involved :");
						text += "<br/><ul>";
						for ( v in u.vendors) {
							text += "<li>" + v + "</li>";
						}
						text += "</ul>";
						
					}else{
						//Distribution notif to the users
						var d = u.distrib;
						text = t._("Do not forget the delivery on <b>::day::</b> from ::from:: to ::to::<br/>", {day:view.dDate(d.date),from:view.hHour(d.date),to:view.hHour(d.end)});
						text += t._("Your products to collect :") + "<br/><ul>";
						for ( p in u.products) {
							text += "<li>"+p.quantity+" x "+p.product.getName();
							// Gerer le cas des contrats en alternance
							if (p.user2 != null) {
								text += " " + t._("alternated with") + " ";
								if (u.user == p.user)
									text += p.user2.getCoupleName();
								else
									text += p.user.getCoupleName();
							}
							text += "</li>";
						}
						text += "</ul>";
					}
				
					try{
						var m = new Mail();
						m.setSender(App.config.get("default_email"), "Cagette.net");
						if(group.contact!=null) m.setReplyTo(group.contact.email, group.name);
						m.addRecipient(u.user.email, u.user.getName());
						if (u.user.email2 != null) m.addRecipient(u.user.email2);
						m.setSubject( group.name+" : "+t._("Distribution on ::date::",{date:app.view.hDate(u.distrib.date)})  );
						m.setHtmlBody( app.processTemplate("mail/message.mtt", { text:text,group:group } ) );
						App.sendMail(m , u.distrib.catalog.group);	
					}catch (e:Dynamic){						
						app.logError(e); //email could be invalid
					}
					
				}
			}
		}
	}
	
	
	/**
	 * Check if there is a multi-distrib to validate.
	 * 
	 * Autovalidate it after 10 days
	 */
	function distribValidationNotif(){
		
		var now = Date.now();

		var from = now.setHourMinute( now.getHours(), 0 );
		var to = now.setHourMinute( now.getHours()+1 , 0);
		
		var explain = t._("<p>This step is important in order to:</p>");
		explain += t._("<ul><li>Update orders if delivered quantities are different from ordered quantities</li>");
		explain += t._("<li>Confirm the reception of payments (checks, cash, transfers) in order to mark orders as 'paid'</li></ul>");
		
		/*
		 * warn administrator if a distribution just ended
		 */ 
		var distribs = db.MultiDistrib.manager.search( !$validated && ($distribStartDate >= from) && ($distribStartDate < to) , false);
		
		for ( d in Lambda.array(distribs)){
			if ( !d.getGroup().hasPayments() ){
				distribs.remove(d);
			}
		}
		

		var view = App.current.view;
		
		for ( d in distribs ){
			
			var subj = t._("[::group::] Validation of the ::date:: distribution",{group : d.getGroup().name , date : view.hDate(d.distribStartDate)});
			
			var url = "http://" + App.config.HOST + "/distribution/validate/"+d.id;
			
			var html = t._("<p>Your distribution just finished, don't forget to <b>validate</b> it</p>");
			html += explain;
			html += t._("<p><a href='::distriburl::'>Click here to validate the distribution</a> (You must be connected to your group Cagette)", {distriburl:url});
			
			App.quickMail(d.getGroup().contact.email, subj, html);
		}
		
		/*
		 * warn administrator if a distribution ended 3 days ago
		 */		
		
		var from = now.setHourMinute( now.getHours() , 0 ).deltaDays(-3);
		var to = now.setHourMinute( now.getHours()+1 , 0).deltaDays(-3);
		
		//warn administrator if a distribution just ended
		var distribs = db.MultiDistrib.manager.search( !$validated && ($distribStartDate >= from) && ($distribStartDate < to) , false);
		
		for ( d in Lambda.array(distribs)){
			if ( !d.getGroup().hasPayments() ){
				distribs.remove(d);
			}
		}
		
		for ( d in distribs ){
		
			var subj = t._("[::group::] Validation of the ::date:: distribution",{group : d.getGroup().name , date : view.hDate(d.distribStartDate)});
			var url = "http://" + App.config.HOST + "/distribution/validate/"+d.id;		
			var html = t._("<p>Reminder: you have a delivery to validate.</p>");
			html += explain;
			html += t._("<p><a href='::distriburl::'>Click here to validate the delivery</a> (You must be connected to your Cagette group)", {distriburl:url});
			
			App.quickMail(d.getGroup().contact.email, subj, html);
		}
		
		
		/*
		 * Autovalidate unvalidated distributions after 10 days
		 */ 
		var from = now.setHourMinute( now.getHours() , 0 ).deltaDays( 0 - db.Distribution.DISTRIBUTION_VALIDATION_LIMIT );
		var to = now.setHourMinute( now.getHours() + 1 , 0).deltaDays( 0 - db.Distribution.DISTRIBUTION_VALIDATION_LIMIT );
		print('<h3>Autovalidation of unvalidated distribs</h3>');
		print('Find distributions from $from to $to');
		var distribs = db.MultiDistrib.manager.search( !$validated && ($distribStartDate >= from) && ($distribStartDate < to) , false);
		for ( d in Lambda.array(distribs)){
			if ( !d.getGroup().hasPayments() ){
				distribs.remove(d);
			}
		}

		for (d in distribs){
			print(d.toString());
			try	{
				service.PaymentService.validateDistribution(d);
			}catch(e:tink.core.Error){
				print(e.message);
				continue;
			}
		}
		//email
		for ( d in distribs ){
			if(d.getGroup().contact==null) continue;
			var subj = t._("[::group::] Validation of the ::date:: distribution",{group : d.getGroup().name , date : view.hDate(d.distribStartDate)});
			var html = t._("<p>As you did not validate it manually after 10 days, <br/>the delivery of the ::deliveryDate:: has been validated automatically</p>", {deliveryDate:App.current.view.hDate(d.distribStartDate)});
			App.quickMail(d.getGroup().contact.email, subj, html);
		}
		
	}
	
	/**
	 * Send emails from buffer.
	 * 
	 * Warning, if the cron is executed each minute, 
	 * you should consider the right amount of emails to send each minute in order to avoid overlaping and getting in concurrency problems.
	 * (like "SELECT * FROM BufferedMail WHERE sdate IS NULL ORDER BY cdate DESC LIMIT 100 FOR UPDATE Lock wait timeout exceeded; try restarting transaction") 
	 */
	function sendEmailsfromBuffer(index:Int){
		printTitle("Send 10 Emails from Buffer");		
		//send
		for( e in sugoi.db.BufferedMail.manager.search($sdate==null,{limit:[index,10],orderBy:-cdate},false)  ){
			e.lock();
			if(e.isSent()) continue;
			
			print('#${e.id} - ${e.title}');
			e.finallySend();
			Sys.sleep(0.1);
		}
	}

	/**
	 *  Email product report when orders close				
	 **/  
	function sendOrdersByProductWhenOrdersClose(){
	
		var range = tools.DateTool.getLastHourRange();
		// Sys.println("Time is "+Date.now()+"<br/>");
		// Sys.println('Find all distributions that have closed in the last hour from ${range.from} to ${range.to} \n<br/>');
				
		for ( d in db.Distribution.manager.search($orderEndDate >= range.from && $orderEndDate < range.to, false)){
			service.OrderService.sendOrdersByProductReport(d);
		}

	}
	
	
	public static function print(text){
		Sys.println( "<pre>"+ text + "</pre><br/>" );
	}

	public static function printTitle(title){
		Sys.println("<h2>"+title+"</h2>");
	}
}
