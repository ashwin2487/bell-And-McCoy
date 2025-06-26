public without sharing class CommissionImportProcess{
    @AuraEnabled
    public static Integer insertCommissionData(List<Map<String, String>> records,Id importRecordId,Integer startLine,Integer endLine) {
        Import__c importRecord;
        
        try {
            importRecord = [SELECT Id, Vendor__c, RecordType.DeveloperName, Total_File_Lines__c FROM Import__c WHERE Id = :importRecordId LIMIT 1];
        } catch (Exception e) {
            throw new AuraHandledException('Error: Import record not found.');
        }
        
        if (importRecord == null || importRecord.RecordType == null || importRecord.RecordType.DeveloperName != 'MoM_Commissions') {
            throw new AuraHandledException('Error: Import record or RecordType is missing OR Only MoM Commission Reports can be processed.');
        }
        if (String.isEmpty(importRecord.Vendor__c)) {
            throw new AuraHandledException('Error: Vendor ID is missing.');
        }
        
        Id vendorId = importRecord.Vendor__c;
        List<Import_MoM_Commission_Data__c> toInsert = new List<Import_MoM_Commission_Data__c>();
        
        for (Map<String, String> row : records) {
            try {
                Import_MoM_Commission_Data__c comissionRecord = new Import_MoM_Commission_Data__c(
                    Dealer_Name__c = row.get('Dealer Name')?.trim(),
                    Sales_Amount__c = safeDecimal(row.get('Sales Amount')),
                    Commission_Amount__c = safeDecimal(row.get('Commission Amount')),
                    Import__c = importRecordId,
                    Vendor__c = vendorId,
                    Data_Import_Status__c = 'Inserted',
                    Line_Number__c = safeInteger(row.get('Line_Number__c'))
                );
                toInsert.add(comissionRecord);
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
            importRecord.Total_File_Lines__c = (importRecord.Total_File_Lines__c == null ? 0 : importRecord.Total_File_Lines__c) + insertedCount;
            
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
}