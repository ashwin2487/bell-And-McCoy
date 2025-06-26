public class moMImportHelper {
    
 public static Map<String, Object> processAndUpdateMoMImportRecord(
        List<Account> zeroDayDataEntryListToInsert, 
        List<Account> mBNameDealerUpdateList,
        String recordTypeId
    ) {
        Map<String, Object> responseMap = new Map<String, Object>();

        try {
            if (zeroDayDataEntryListToInsert != null && !zeroDayDataEntryListToInsert.isEmpty()) {
                Import__c zeroDayImportRecord = createImportRecord(zeroDayDataEntryListToInsert, recordTypeId);
                updateAccountRecords(zeroDayDataEntryListToInsert, zeroDayImportRecord);
                responseMap.put('zeroDayImportRecord', zeroDayImportRecord);
                responseMap.put('zeroDayUpdatedDealers', zeroDayDataEntryListToInsert);
            }
            if (mBNameDealerUpdateList != null && !mBNameDealerUpdateList.isEmpty()) {
                Import__c mbNameImportRecord = createImportRecord(mBNameDealerUpdateList, recordTypeId);
                updateAccountRecords(mBNameDealerUpdateList, mbNameImportRecord);
                responseMap.put('mBNameImportRecord', mbNameImportRecord);
                responseMap.put('mBNameUpdatedDealers', mBNameDealerUpdateList);
            }
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
            responseMap.put('error', e.getMessage());
        }
        return responseMap;
    }
    public static Map<String, Object> processMatchedDealersForLWC(
        List<Account> existingMatchedDealerDataToLWC,
        String recordTypeId
    ) {
        Map<String, Object> responseMap = new Map<String, Object>();
        try {
            if (existingMatchedDealerDataToLWC != null && !existingMatchedDealerDataToLWC.isEmpty()) {
                Import__c matchedDealerImportRecord = createImportRecord(existingMatchedDealerDataToLWC, recordTypeId);
                updateAccountRecords(existingMatchedDealerDataToLWC, matchedDealerImportRecord);
                responseMap.put('matchedDealerImportRecord', matchedDealerImportRecord);
                responseMap.put('matchedDealerUpdatedDealers', existingMatchedDealerDataToLWC);
            }
        } catch (Exception e) {
            System.debug('An error occurred: ' + e.getMessage());
            responseMap.put('error', e.getMessage());
        }
        return responseMap;
    }
    private static Import__c createImportRecord(List<Account> dealerList, String recordTypeId) {
        Import__c newImportRecord = new Import__c();
        Account firstDealer = dealerList[0];
        newImportRecord.Connected_Vendor__c = firstDealer.Vendor_Name__c;
        newImportRecord.Invoice_Start_Date__c = firstDealer.Invoice_Start_Date__c;
        newImportRecord.Invoice_End_Date__c = firstDealer.Invoice_End_Date__c;
        newImportRecord.MoM_Report_Date__c = firstDealer.MoM_Report_Date__c;
        newImportRecord.RecordTypeId = recordTypeId;
        insert newImportRecord;
        System.debug('Successfully created Import__c record: ' + newImportRecord);
        return newImportRecord;
    }
    private static void updateAccountRecords(List<Account> accountsToUpdate, Import__c importRecord) {
        for (Account dealer : accountsToUpdate) {
            dealer.Import_Record_Id__c = importRecord.Id;
        }
        if (!accountsToUpdate.isEmpty()) {
            update accountsToUpdate;
            System.debug('Successfully updated accounts with Import__c record ID.');
        }
    }
}