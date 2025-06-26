/**
 * Auto Generated and Deployed by the Declarative Lookup Rollup Summaries Tool package (dlrs)
 **/
@IsTest
private class dlrs_Storyteller_BrandTest
{
    @IsTest
    private static void testTrigger()
    {
        // Force the dlrs_Storyteller_BrandTrigger to be invoked, fails the test if org config or other Apex code prevents this.
        dlrs.RollupService.testHandler(new Storyteller_Brand__c());
    }
}