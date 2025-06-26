@isTest
private class DealerImportProcessTest {
    
    @testSetup
    static void setupData() {
        // Query the existing record type instead of inserting
        RecordType rt = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Import__c' AND DeveloperName = 'Sales_Monthly_Summaries' 
            LIMIT 1
        ];
        
        // Create Vendor
        Vendor__c vendor = new Vendor__c(Name = 'Test Vendor');
        insert vendor;
        
        // Create Import__c
        Import__c imp = new Import__c(
            Vendor__c = vendor.Id,
            RecordTypeId = rt.Id
        );
        insert imp;
    }
    
    @isTest
    static void testInsertDealerDataSuccess() {
        Import__c imp = [SELECT Id FROM Import__c LIMIT 1];
        
        // Create and format the date
        Date invoiceDate = Date.newInstance(2023, 8, 6);
        String inputDate = twoDigit(invoiceDate.month()) + '-' + twoDigit(invoiceDate.day()) + '-' + invoiceDate.year();
        
        List<Map<String, String>> mockRecords = new List<Map<String, String>>();
        Map<String, String> row = new Map<String, String>{
            'Dealer Name' => 'Test Dealer',
                'Invoice Date' => inputDate,
                'Invoice Number' => 'INV-001',
                'Product SKU' => 'SKU-123',
                'Product Quantity' => '10',
                'Unit Price' => '25.5',
                'Commission Received' => '5.5',
                'Account Number' => 'ACC123',
                'PO Number' => 'PO-789',
                'Job Name' => 'Test Job',
                'Project' => 'Project X',
                'Line_Number__c' => '1'
                };
                    mockRecords.add(row);
        
        Test.startTest();
        Integer result = DealerImportProcess.insertDealerData(mockRecords, imp.Id, 1, 1);
        Test.stopTest();
        
        System.assertEquals(1, result, 'One record should be inserted.');
        
        List<Dealer_Import_Data__c> inserted = [
            SELECT Id, Dealer_Name__c FROM Dealer_Import_Data__c WHERE Import__c = :imp.Id
        ];
        System.assertEquals(1, inserted.size());
        System.assertEquals('Test Dealer', inserted[0].Dealer_Name__c);
    }
    
    // Helper method to manually pad month/day
    private static String twoDigit(Integer num) {
        return num < 10 ? '0' + String.valueOf(num) : String.valueOf(num);
    }
    
    
    @isTest
    static void testInvalidRecordTypeError() {
        // Create Import__c with wrong RecordType
        RecordType invalidRT = [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = 'Import__c' 
            AND DeveloperName != 'Sales_Monthly_Summaries' 
            LIMIT 1
        ];
        
        Vendor__c vendor = [SELECT Id FROM Vendor__c LIMIT 1];
        
        Import__c imp = new Import__c(
            RecordTypeId = invalidRT.Id, 
            Vendor__c = vendor.Id
        );
        insert imp;
        
        Test.startTest();
        try {
            DealerImportProcess.insertDealerData(new List<Map<String, String>>(), imp.Id, 1, 1);
            System.assert(false, 'Expected exception for invalid record type');
        } catch (AuraHandledException ex) {
            System.assertEquals('Script-thrown exception',ex.getMessage());
        }
        Test.stopTest();
    }
    
    @isTest
    static void testInvalidRowSkipped() {
        Import__c imp = [SELECT Id FROM Import__c LIMIT 1];
        
        List<Map<String, String>> records = new List<Map<String, String>>();
        // This will throw exception when parsing integer/decimal
        records.add(new Map<String, String>{
            'Dealer Name' => 'Test Dealer',
                'Product Quantity' => 'INVALID',
                'Unit Price' => 'INVALID',
                'Commission Received' => 'INVALID'
                });
        
        Test.startTest();
        Integer inserted = DealerImportProcess.insertDealerData(records, imp.Id, 1, 1);
        Test.stopTest();
        
        System.assertEquals(1, inserted, 'Record should still be inserted with fallback values.');
    }
}