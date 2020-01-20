package service;

class MembershipService{

    var group : db.Group;

    public function new(group:db.Group){
        this.group = group;
    }


    public function countUpToDateMemberships(){
		var year = group.getMembershipYear();
		return db.Membership.manager.count( $amap == group && $year == year);
    }
    
    /**
        get members with up to date membership
    **/
    public function getMembershipUsers(?index:Int,?limit:Int):Array<db.User> {
		var userGroups = [];
		if (index == null && limit == null) {
			userGroups = db.UserGroup.manager.search($group == group, false).array();	
		}else {
			userGroups = db.UserGroup.manager.search($group == group,{limit:[index,limit]}, false).array();
		}
		
		for (userGroup in Lambda.array(userGroups)) {
			if (!userGroup.hasValidMembership()) userGroups.remove(userGroup);
		}
		
		return userGroups.map( x -> return x.user );	
	}

    /**
        get members with no membership ( or expired )
    **/
	public function getNoMembershipUsers(?index:Int,?limit:Int):Array<db.User> {
		var userGroups = [];
		if (index == null && limit == null) {
			userGroups = db.UserGroup.manager.search($group == group, false).array();	
		}else {
			userGroups = db.UserGroup.manager.search($group == group,{limit:[index,limit]}, false).array();
		}
		
		for (userGroup in Lambda.array(userGroups)) {
			if (userGroup.hasValidMembership()) userGroups.remove(userGroup);
		}
		
		return userGroups.map( x -> return x.user );		
	}
}