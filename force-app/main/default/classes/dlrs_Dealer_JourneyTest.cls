/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Dealer_JourneyTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_Dealer_JourneyTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Dealer_Journey__c());
    }
}