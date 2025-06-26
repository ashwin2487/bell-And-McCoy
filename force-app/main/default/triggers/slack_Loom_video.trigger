trigger slack_Loom_video on useloom__loom_video__c (after insert, after update, before delete) {
	if(trigger.isAfter && trigger.isInsert || trigger.isAfter && trigger.isUpdate || trigger.isBefore && trigger.isDelete) {
		slackv2__.utilities.startSubscriptionQueue(trigger.newMap, trigger.oldMap, trigger.operationType, 'useloom__loom_video__c');
	}
}