@isTest
public class deleteRecordsControllerTest {
    
    private static Id validImportId;
    private static Id invalidImportId;
    private static Id validRecordTypeId;
    
    @testSetup
    static void setupTestData() {
        // Create a sample Vendor__c record
        Vendor__c vendor = new Vendor__c(Name = 'Test Vendor');
        insert vendor;
        
        // Fetch RecordTypeId for 'Sales_Monthly_Summaries'
        RecordType salesMonthlyRT = [SELECT Id FROM RecordType  WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1];
        validRecordTypeId = salesMonthlyRT.Id;
        
        // Create a valid Import__c record (with Sales_Monthly_Summaries RecordType)
        Import__c validImport = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = validRecordTypeId,
            Status__c = 'Incomplete'
        );
        insert validImport;
        validImportId = validImport.Id; 
        List<Dealer_Import_Data__c> importDataList = new List<Dealer_Import_Data__c>();
        for (Integer i = 0; i < 5; i++) {
            importDataList.add(new Dealer_Import_Data__c(
                Dealer_Name__c = 'Test Dealer ' + i,
                Invoice_Date__c = Date.today(),
                Invoice_Number__c = 'INV-00' + i,
                Product_SKU__c = 'SKU-00' + i,
                Product_Quantity__c = 2,
                Unit_Price__c = 100,
                Commission_Received__c = 10,
                Account_Number__c = null,
                Import__c = validImportId,
                Vendor__c = vendor.Id,
                Data_Import_Status__c = 'Account Number - Null'
            ));
        }
        insert importDataList;
        
        RecordType otherRT = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Import__c' 
            AND DeveloperName != 'Sales_Monthly_Summaries' 
            LIMIT 1
        ];
        
        Import__c invalidImport = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = otherRT.Id,
            Status__c = 'Incomplete'
        );
        insert invalidImport;
        invalidImportId = invalidImport.Id;
    }
    
    @isTest
    static void testDeleteWithValidRecordType() {
        
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c imp = [SELECT Id FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        
        Integer beforeCount = [SELECT COUNT() FROM Dealer_Import_Data__c WHERE Import__c = :imp.Id];
        System.assertEquals(5, beforeCount, 'Expected 5 records before deletion');
        
        Test.startTest();
        String jobId = deleteRecordsController.deleteImportDealerData(imp.Id);
        Test.stopTest();
        
        System.assertNotEquals(null, jobId, 'Expected a non-null Batch Job ID');
        
        List<Dealer_Import_Data__c> remaining = [SELECT Id FROM Dealer_Import_Data__c WHERE Import__c = :imp.Id];
        System.assertEquals(0, remaining.size(), 'All related records should be deleted');
    }
    
    @isTest
    static void testDeleteWithInvalidRecordType() {
        Test.startTest();
        
        try {
            deleteRecordsController.deleteImportDealerData(invalidImportId);
            System.assert(false, 'Expected an exception to be thrown for invalid record type');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 
                          'Exception message should indicate that only Sales Monthly Summaries can be processed.');
        }
        Test.stopTest();
    }
    
    @isTest
    static void testDeleteWithBlankImportId() {
        Test.startTest();
        
        try {
            deleteRecordsController.deleteImportDealerData('');
            System.assert(false, 'Expected an exception to be thrown for blank Import ID');
        } catch (AuraHandledException e) {
            System.assert(e.getMessage().contains('Script-thrown exception'), 'Exception should indicate that Import Record Id is required');
        }
        Test.stopTest();
    }
}