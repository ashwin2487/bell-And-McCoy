public with sharing class DealerImportProcess {
    @AuraEnabled
    public static Integer insertDealerData(
        List<Map<String, String>> records,
        Id importRecordId,
        Integer startLine,
        Integer endLine
    ) {
        Import__c importRecord;
        
        try {
            importRecord = [
                SELECT Id, Vendor__c, RecordType.DeveloperName, Total_File_Lines__c
                FROM Import__c 
                WHERE Id = :importRecordId 
                LIMIT 1
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error: Import record not found.');
        }
        
        if (importRecord == null || importRecord.RecordType == null || importRecord.RecordType.DeveloperName != 'Sales_Monthly_Summaries') {
            throw new AuraHandledException('Error: Import record or RecordType is missing OR Only Sales Monthly Summary records can be processed.');
        }
        if (String.isEmpty(importRecord.Vendor__c)) {
            throw new AuraHandledException('Error: Vendor ID is missing.');
        }
        
        Id vendorId = importRecord.Vendor__c;
        List<Dealer_Import_Data__c> toInsert = new List<Dealer_Import_Data__c>();
        
        for (Map<String, String> row : records) {
            try {
                Dealer_Import_Data__c dealerRec = new Dealer_Import_Data__c(
                    Dealer_Name__c = row.get('Dealer Name')?.trim(),
                    Invoice_Date__c = parseDate(row.get('Invoice Date')),
                    Invoice_Number__c = row.get('Invoice Number')?.trim(),
                    Product_SKU__c = row.get('Product SKU')?.trim(),
                    Product_Quantity__c = safeInteger(row.get('Product QTY')),
                    Unit_Price__c = safeDecimal(row.get('Unit Price')),
                    Commission_Received__c = safeDecimal(row.get('Commission')),
                    Account_Number__c = row.get('Account Number')?.trim(),
                    PO_Number__c = row.get('PO Number')?.trim(),
                    Job_Name__c = row.get('Job Name')?.trim(),
                    Project__c = row.get('Project')?.trim(),
                    Import__c = importRecordId,
                    Vendor__c = vendorId,
                    Data_Import_Status__c = 'Inserted',
                    Line_Number__c = safeInteger(row.get('Line_Number__c'))
                );
                toInsert.add(dealerRec);
            } catch (Exception e) {
                System.debug('Skipping row due to error: ' + e.getMessage());
            }
        }
        
        Integer insertedCount = 0;
        
        if (!toInsert.isEmpty()) {
            insert toInsert;
            insertedCount = toInsert.size();
        }
        
        if (insertedCount > 0) {
            importRecord.Total_File_Lines__c = 
                (importRecord.Total_File_Lines__c == null ? 0 : importRecord.Total_File_Lines__c) + insertedCount;
            
            update importRecord;
        }
        
        return insertedCount;
    }
    
    
    private static Integer safeInteger(String val) {
        try {
            return val != null ? Integer.valueOf(val.trim()) : 0;
        } catch (Exception e) {
            return 0;
        }
    }
    
    private static Decimal safeDecimal(String val) {
        try {
            return val != null ? Decimal.valueOf(val.trim()) : 0;
        } catch (Exception e) {
            return 0;
        }
    }
    private static Date parseDate(String val) {
        if (String.isBlank(val)) return null;
        
        try {
            val = val.trim();
            
            // Normalize the format to use dashes
            val = val.replace('/', '-');
            
            List<String> parts = val.split('-');
            if (parts.size() == 3) {
                Integer month = Integer.valueOf(parts[0]);
                Integer day = Integer.valueOf(parts[1]);
                Integer year = Integer.valueOf(parts[2]);
                
                return Date.newInstance(year, month, day);
            }
        } catch (Exception e) {
            System.debug('Date parse error for value: ' + val + ' — ' + e.getMessage());
        }
        
        return null;
    }
    
}