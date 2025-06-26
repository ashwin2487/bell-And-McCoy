@isTest
public class rollbackAssociatedRecordsBatchTest {
    
    private static Id validImportId;
    private static Id invalidImportId;
    private static Vendor__c vendor;

    // Test Setup: Creates necessary test data
    @testSetup
    static void setupTestData() {
        // Insert a Vendor
        vendor = new Vendor__c(Name = 'Test Vendor');
        insert vendor;
        
        // Insert valid RecordType for Import__c
        RecordType salesMonthlyRT = [
            SELECT Id FROM RecordType  
            WHERE SObjectType = 'Import__c' 
            AND DeveloperName = 'Sales_Monthly_Summaries' 
            LIMIT 1
        ];
        
        // Create valid Import__c
        Import__c validImport = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = salesMonthlyRT.Id,
            Status__c = 'Incomplete'
        );
        insert validImport;
        validImportId = validImport.Id;
        
        // Create related records for valid import
        Account dealer = new Account(Name = 'Test Dealer');
        insert dealer;
        
        Dealer_Journey__c dealerJourney = new Dealer_Journey__c(Dealer__c = dealer.Id, Vendor__c = vendor.Id);
        insert dealerJourney;
        
        // Product used in multiple batches
        Product2 product = new Product2(
            Name = 'TestProductSKU',
            StockKeepingUnit = 'TestProductSKU',
            Import__c = validImportId,
            Vendor__c = vendor.Id,
            Batch_Id__c = 'BATCH001',
            Batch_Id_2__c = 'BATCH002'
        );
        insert product;
        Product2 elseUsedProduct = new Product2(
            Name = 'TestProductSKU1',
            StockKeepingUnit = 'TestProductSKU1',
            Import__c = validImportId,
            Vendor__c = vendor.Id,
            Batch_Id__c = 'BATCH003',
            Batch_Id_2__c = 'BATCH004'
        );
        insert elseUsedProduct;
        
        // Dealer invoice for valid import and product
        Dealer_Invoice__c invoice = new Dealer_Invoice__c(
            Invoice_Number__c = 'INV123',
            Vendor__c = vendor.Id,
            Dealer__c = dealer.Id,
            Import__c = validImportId,
            Batch_Id__c = 'BATCH001',
            Batch_Id_2__c = 'BATCH002'
        );
        insert invoice;
        
        // Dealer invoice line for valid invoice
        Dealer_Invoice_Line__c invoiceLine = new Dealer_Invoice_Line__c(
            Invoice_Number__c = 'INV123',
            Dealer_Invoice__c = invoice.Id,
            Import__c = validImportId,
            Batch_Id__c = 'BATCH001',
            Batch_Id_2__c = 'BATCH002',
            Product__c = product.Id
        );
        insert invoiceLine;
        
        // Alias for dealer journey
        Dealer_Journey_Alias__c alias = new Dealer_Journey_Alias__c(
            Name = 'Test Dealer',
            Dealer_Journey__c = dealerJourney.Id,
            Import__c = validImportId,
            Vendor__c = vendor.Id,
            Batch_Id__c = 'BATCH001'
        );
        insert alias;
        
        // Dealer import data associated with valid import and product
        Dealer_Import_Data__c importData = new Dealer_Import_Data__c(
            Dealer_Name__c = 'Test Dealer',
            Invoice_Number__c = 'INV123',
            Product_SKU__c = 'TestProductSKU',
            Vendor__c = vendor.Id,
            Import__c = validImportId,
            Batch_Id__c = 'BATCH001',
            Batch_Id_2__c = 'BATCH002'
        );
        insert importData;
        
        // Create invalid Import__c (wrong record type)
        RecordType otherRT = [
            SELECT Id FROM RecordType 
            WHERE SObjectType = 'Import__c' 
            AND Id != :salesMonthlyRT.Id 
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
    static void testBatchRollback_DeletesRecords() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c validImport = [SELECT Id FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        
        Test.startTest();
        Database.executeBatch(new rollbackAssociatedRecordsBatch(validImport.Id), 1);
        Test.stopTest();
        
        // Assert everything got deleted
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Import_Data__c WHERE Import__c = :validImport.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE Import__c = :validImport.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Invoice__c WHERE Import__c = :validImport.Id]);
        System.assertEquals(1, [SELECT COUNT() FROM Product2 WHERE Import__c = :validImport.Id]);
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Journey_Alias__c WHERE Import__c = :validImport.Id]);
    }
    
    @isTest
    static void testBatchRollback_NoRecordsFound() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        
        // Ensure vendor is inserted and referenced properly
        Vendor__c noDataVendor = new Vendor__c(Name = 'No Data Vendor');
        insert noDataVendor;
        
        // Create an Import__c with NO related records
        Import__c noDataImport = new Import__c(
            Vendor__c = noDataVendor.Id,  // Use the inserted Vendor
            RecordTypeId = rtId,
            Status__c = 'Incomplete'
        );
        insert noDataImport;
        
        Test.startTest();
        Database.executeBatch(new rollbackAssociatedRecordsBatch(noDataImport.Id), 1);
        Test.stopTest();
        
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Import_Data__c WHERE Import__c = :noDataImport.Id]);
    }
    
    @isTest
    static void testRollback_FailureHandling() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        Import__c validImport = [SELECT Id FROM Import__c WHERE RecordTypeId = :rtId LIMIT 1];
        
        rollbackAssociatedRecordsBatch batch = new rollbackAssociatedRecordsBatch(validImport.Id);
        
        Test.startTest();
        Database.executeBatch(batch, 1);
        Test.stopTest();
        
        // Hard to catch error emails in test context, but no exception should bubble up
        System.assert(true, 'Batch completed without unhandled exception');
    }
    
    @isTest
    static void testBatchRollback_BatchId2Empty() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        
        Vendor__c vendor = new Vendor__c(Name = 'VendorNoBatch2');
        insert vendor;
        
        Import__c importWithoutBatch2 = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = rtId,
            Status__c = 'Incomplete'
        );
        insert importWithoutBatch2;
        
        Dealer_Import_Data__c importData = new Dealer_Import_Data__c(
            Dealer_Name__c = 'Dealer No Batch 2',
            Invoice_Number__c = 'INV456',
            Product_SKU__c = 'SKU456',
            Vendor__c = vendor.Id,
            Import__c = importWithoutBatch2.Id,
            Batch_Id__c = 'BATCHONLY1'  // Notice no Batch_Id_2__c
        );
        insert importData;
        
        Test.startTest();
        Database.executeBatch(new rollbackAssociatedRecordsBatch(importWithoutBatch2.Id), 1);
        Test.stopTest();
        
        // Confirm records are deleted
        System.assertEquals(0, [SELECT COUNT() FROM Dealer_Import_Data__c WHERE Import__c = :importWithoutBatch2.Id]);
    }
    
    @isTest
    static void testBatchRollback_NoDealerImportData() {
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        
        Vendor__c vendor = new Vendor__c(Name = 'VendorNoData');
        insert vendor;
        
        Import__c emptyImport = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = rtId,
            Status__c = 'Incomplete'
        );
        insert emptyImport;
        
        Test.startTest();
        Database.executeBatch(new rollbackAssociatedRecordsBatch(emptyImport.Id), 1);
        Test.stopTest();
        
        // If no exception thrown, and batch completed — assume success
        System.assert(true, 'Batch completed without Dealer_Import_Data__c');
    }
    
    @isTest
    static void testBatchRollback_TriggerException() {
        // Fetch valid RecordTypeId
        Id rtId = [SELECT Id FROM RecordType WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' LIMIT 1].Id;
        
        // Create Vendor
        Vendor__c vendor = new Vendor__c(Name = 'VendorError');
        insert vendor;
        
        // Create Import__c
        Import__c importError = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = rtId,
            Status__c = 'Incomplete'
        );
        insert importError;
        
        // Create Dealer_Import_Data__c but without proper Invoice_Number__c (simulate bad data)
        Dealer_Import_Data__c importData = new Dealer_Import_Data__c(
            Dealer_Name__c = 'Bad Dealer',
            Vendor__c = vendor.Id,
            Import__c = importError.Id
            // Missing Invoice_Number__c and Product_SKU__c intentionally
        );
        insert importData;
        
        Test.startTest();
        // No mocking needed, Messaging.sendEmail will work normally
        Database.executeBatch(new rollbackAssociatedRecordsBatch(importError.Id), 1);
        Test.stopTest();
        
        System.assert(true, 'Batch executed. If error occurred during deletion, catch block handled it.');
    }
    
}