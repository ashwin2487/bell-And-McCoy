@isTest(SeeAllData=false)
public class SkippedRecordsControllerTest {
    private static Id validRecordTypeId;
    private static Account_Number__c existingAcct;
    @testSetup
    static void setupTestData() {
        
        Vendor__c vendor = new Vendor__c(Name = 'Test Vendor');
        insert vendor;
        
        RecordType salesMonthlyRT = [SELECT Id FROM RecordType  WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1];
        validRecordTypeId = salesMonthlyRT.Id;
        Import__c imp = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = validRecordTypeId,
            Status__c = 'Incomplete'
        );
        insert imp;
        
        Account dealer = new Account(Name = 'Test Dealer');
        insert dealer;
        
        
        Dealer_Journey__c journey = new Dealer_Journey__c(
            Dealer__c = dealer.Id,
            Vendor__c = vendor.Id,
            Active__c = false
        );
        insert journey;
        
        
        Dealer_Journey_Alias__c aliasRec = new Dealer_Journey_Alias__c(
            Name = 'Test Dealer',
            Dealer_Journey__c = journey.Id,
            vendor__c = vendor.Id
        );
        insert aliasRec;
        existingAcct = new Account_Number__c(
            Dealer__c = dealer.Id,
            Account_Number__c = 'ACCT001',
            Vendor__c = vendor.Id,
            Dealer_Journey__c = journey.Id,
            Active__c = true
        );
        insert existingAcct;
        
        List<Dealer_Import_Data__c> importDataList = new List<Dealer_Import_Data__c>();
        
        importDataList.add(new Dealer_Import_Data__c(
            Dealer_Name__c = 'Test Dealer',
            Invoice_Date__c = Date.today(),
            Invoice_Number__c = 'INV-001',
            Product_SKU__c = 'SKU-001',
            Product_Quantity__c = 2,
            Unit_Price__c = 100,
            Commission_Received__c = 10,
            Account_Number__c = 'ACCT001',
            Import__c = imp.Id,
            Vendor__c = vendor.Id,
            Data_Import_Status__c = 'Account Number - Null'
        ));
        
        importDataList.add(new Dealer_Import_Data__c(
            Dealer_Name__c = 'Unknown Dealer',
            Invoice_Date__c = Date.today(),
            Invoice_Number__c = 'INV-002',
            Product_SKU__c = 'SKU-002',
            Product_Quantity__c = 1,
            Unit_Price__c = 200,
            Commission_Received__c = 20,
            Account_Number__c = 'ACCT001',
            Import__c = imp.Id,
            Vendor__c = vendor.Id,
            Data_Import_Status__c = 'Account Number - Null'
        ));
        insert importDataList;
    }
    
    static testMethod void testProcessRecordsSkipped_Positive_NewInvoice() {
        
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c imp = [SELECT Id FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        
        Test.startTest();
        SkippedRecordsController.SkippedRecordsResponse response = SkippedRecordsController.processRecordsSkipped(imp.Id);
        Test.stopTest();
        
        
        System.assertNotEquals(null, response.batchJobId, 'Batch Job ID should not be null');
        System.assertEquals('Batch job started successfully.', response.message);
        
        
        Integer invCount = [SELECT COUNT() FROM Dealer_Invoice__c WHERE Import__c = :imp.Id];
        Integer lineCount = [SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE Import__c = :imp.Id];
        System.assertEquals(2, invCount, 'One new invoice should be created');
        System.assertEquals(2, lineCount, 'One new invoice line should be created');
    }
    
    static testMethod void testProcessRecordsSkipped_Positive_ExistingInvoice() {
        
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c imp = [SELECT Id FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        Dealer_Invoice__c existingInv = new Dealer_Invoice__c(
            Invoice_Date__c = Date.today(),
            Invoice_Number__c = 'INV-001',
            Dealer__c = [SELECT Dealer__c FROM Dealer_Journey__c LIMIT 1].Dealer__c,
            Vendor__c = [SELECT Vendor__c FROM Dealer_Journey__c LIMIT 1].Vendor__c,
            Import__c = imp.Id
        );
        insert existingInv;
        
        Test.startTest();
        SkippedRecordsController.SkippedRecordsResponse response = SkippedRecordsController.processRecordsSkipped(imp.Id);
        Test.stopTest();
        
        
        Integer invCount = [SELECT COUNT() FROM Dealer_Invoice__c WHERE Import__c = :imp.Id];
        Integer lineCount = [SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE Import__c = :imp.Id];
        System.assertEquals(2, invCount, 'Existing invoice should be reused');
        System.assertEquals(2, lineCount, 'One invoice line should be created for existing invoice');
    }
    
    static testMethod void testProcessRecordsSkipped_Negative_BlankId() {
        
        try {
            SkippedRecordsController.processRecordsSkipped('');
            System.assert(false, 'Expected AuraHandledException was not thrown');
        } catch (AuraHandledException ex) {
            System.assertEquals('Script-thrown exception', ex.getMessage());
        }
    }
    static testMethod void testProcessRecordsSkipped_InvoiceExistsDifferentVendor() {
        
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c imp = [SELECT Id, Vendor__c FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        
        Dealer_Journey__c journey = [SELECT Id, Dealer__c FROM Dealer_Journey__c LIMIT 1];
        
        Vendor__c otherVendor = new Vendor__c(Name = 'Different Vendor');
        insert otherVendor;
        
        Dealer_Invoice__c conflictingInvoice = new Dealer_Invoice__c(
            Invoice_Number__c = 'INV-001',
            Invoice_Date__c = Date.today(),
            Dealer__c = journey.Dealer__c,
            Vendor__c = otherVendor.Id
        );
        insert conflictingInvoice;
        
        
        Test.startTest();
        SkippedRecordsController.SkippedRecordsResponse response = SkippedRecordsController.processRecordsSkipped(imp.Id);
        Test.stopTest();
        Integer invCount = [
            SELECT COUNT() FROM Dealer_Invoice__c 
            WHERE Import__c = :imp.Id AND Invoice_Number__c = 'INV-001' AND Vendor__c = :imp.Vendor__c
        ];
        System.assertEquals(1, invCount, 'Expected new invoice to be created for correct vendor, not reused from other vendor');
        
        Integer lineCount = [SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE Import__c = :imp.Id];
        System.assertEquals(2, lineCount, 'Expected invoice lines to be created for skipped records');
    }
    
}