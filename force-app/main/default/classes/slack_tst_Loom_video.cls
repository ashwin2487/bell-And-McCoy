@isTest
public class slack_tst_Loom_video {
	@isTest 
	static void testTrigger() {
		useloom__loom_video__c obj0 = new useloom__loom_video__c(
			useloom__shared_link_id_and_email__c = 's'
		);
		insert obj0;
	}
}