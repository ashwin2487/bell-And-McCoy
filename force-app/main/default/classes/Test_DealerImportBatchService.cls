@isTest
private class Test_DealerImportBatchService {
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
    
    @isTest
    static void testRunBatch() {
        // Get the import record ID
        Id importRecordId = [SELECT Id FROM Import__c LIMIT 1].Id;
        
        
        Test.startTest();
        DealerImportBatch batchJob = new DealerImportBatch(importRecordId, 200);
        Test.stopTest();
        
        // Assert results (lines and invoices created)
        List<Dealer_Invoice__c> invoices = [ SELECT Id, Invoice_Number__c FROM Dealer_Invoice__c];
        System.assertEquals(2, invoices.size(), 'Two invoices should be created.');
        
        List<Dealer_Invoice_Line__c> lines = [
            SELECT Id FROM Dealer_Invoice_Line__c
        ];
        System.assert(lines.size() > 0, 'Invoice lines should be inserted.');
    }
    
    @isTest
    static void testRunBatchWithoutImportId() {
        Test.startTest();
        try {
            DealerImportBatch batchJob = new DealerImportBatch(null, null);
            System.assert(false, 'Should have thrown AuraHandledException');
        } catch (AuraHandledException e) {
            System.assertEquals('Import record ID is required.', e.getMessage());
        }
        Test.stopTest();
    }
}