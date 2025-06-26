public class DealerImportBatch implements Database.Batchable<String> {
    private Blob fileBlob;
    private String batchImportId; 
    private Id strVendorId;
    
    public DealerImportBatch(Blob fileBlob, String batchImportId, Id strVendorId) {
        this.fileBlob = fileBlob;
        this.batchImportId = batchImportId;
        this.strVendorId = strVendorId;
    }
    public Iterable<String> start(Database.BatchableContext BC) {
        String fileContent = fileBlob.toString().replace('\r', '');
        
        List<String> lines = new List<String>();
        String currentLine = '';
        
        for (Integer i = 0; i < fileContent.length(); i++) {
            String ch = fileContent.substring(i, i + 1);
            
            if (ch == '\n') {
                lines.add(currentLine);
                currentLine = '';
            } else {
                currentLine += ch;
            }
        }
        if (!String.isEmpty(currentLine)) { 
            lines.add(currentLine); 
        }
        
        System.debug('Total Lines Read: ' + lines.size());
        
        if (!lines.isEmpty()) {
            lines.remove(0);
        }
        
        return lines;
    }
    
    public void execute(Database.BatchableContext BC, List<String> records) {
        List<Dealer_Import_Data__c> dealerRecordsList = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> nullAccountNumberData = new List<Dealer_Import_Data__c>();
        
        System.debug('🚀 Processing Records Batch: ' + records.size());
        
        for (String dealerRecord : records) {
            try {
                dealerRecord = dealerRecord.trim();
                
                if (String.isBlank(dealerRecord)) {
                    System.debug('Skipping Blank Line');
                    continue;
                }
                
                List<String> dealerInfo = parseCSVLine(dealerRecord);
                System.debug('Parsed CSV Data: ' + dealerInfo);
                
                if (dealerInfo.size() < 7) {
                    System.debug('Skipping Record Due to Insufficient Data: ' + dealerRecord);
                    continue;
                }
                Date invoiceDate;
                try {
                    invoiceDate = parseDate(dealerInfo[1]);
                } catch (IllegalArgumentException e) {
                    throw new IllegalArgumentException('Invalid Date Format for Record: ' + dealerRecord + ' | Error: ' + e.getMessage());
                }
                
                Dealer_Import_Data__c dealerRec = new Dealer_Import_Data__c(
                    Dealer_Name__c = dealerInfo[0].trim(),
                    Invoice_Date__c = invoiceDate,
                    Invoice_Number__c = dealerInfo[2].trim(),
                    Product_SKU__c = dealerInfo[3].trim(),
                    Product_Quantity__c = String.isBlank(dealerInfo[4]) ? 0 : safeInteger(dealerInfo[4]),
                    Unit_Price__c = safeDecimal(dealerInfo[5]),
                    Commission_Received__c = safeDecimal(dealerInfo[6]),
                    Account_Number__c = String.isBlank(dealerInfo[7]) ? null : dealerInfo[7].trim(),
                    Batch_Import_Id__c = batchImportId,
                    Vendor__c = strVendorId,
                    Data_Import_Status__c = 'Inserted'
                );
                
                dealerRecordsList.add(dealerRec);
                
            } catch (IllegalArgumentException e) {
                System.debug('Error Processing Record: ' + dealerRecord + ' | Exception: ' + e.getMessage());
            } catch (Exception e) {
                System.debug('Unexpected Error Processing Record: ' + dealerRecord + ' | Exception: ' + e.getMessage());
            }
        }
        System.debug('Records to Insert: ' + dealerRecordsList.size());
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        List<Id> insertedRecordIds = new List<Id>();
        for (RecordType rt : [SELECT Id, DeveloperName FROM RecordType WHERE SObjectType IN ('Account', 'Dealer_Journey__c', 'Import__c')]) {
            recordTypeMap.put(rt.DeveloperName, rt.Id);
        }
        
        // step 1 : processing imported records , on the basis of account numbers, if the account numbers exist in the system and match they will be processed else skipped and process later in step 2.
        List<Dealer_Import_Data__c> importedDataList = new List<Dealer_Import_Data__c>();
        Map<String, Dealer_Import_Data__c> importedDealerDataNameMap = new Map<String,Dealer_Import_Data__c>();
        Map<String, Dealer_Import_Data__c> importedDealerProductMap = new Map<String,Dealer_Import_Data__c>();
        Map<String, Dealer_Import_Data__c> importedDealerAccountNumberMap = new Map<String,Dealer_Import_Data__c>();
        Map<String, Dealer_Import_Data__c> importedInvoiceNumberMap = new Map<String,Dealer_Import_Data__c>();
        Map<String, Dealer_Import_Data__c> importedDealerAccountNumberNullMap = new Map<String,Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> failedRecords = new List<Dealer_Import_Data__c>();
        
        if (!dealerRecordsList.isEmpty()) {
            Database.SaveResult[] results = Database.insert(dealerRecordsList, false);
            for (Integer i = 0; i < results.size(); i++) {
                Dealer_Import_Data__c dealerRecord = dealerRecordsList[i];
                if (results[i].isSuccess()) {
                    Id insertedId = results[i].getId();
                    insertedRecordIds.add(insertedId);
                    
                    importedDataList.add(dealerRecord);
                    importedDealerProductMap.put(dealerRecord.Product_SKU__c, dealerRecord);
                    importedDealerDataNameMap.put(dealerRecord.Dealer_Name__c, dealerRecord);
                    
                    if (dealerRecord.Account_Number__c != null) {
                        importedDealerAccountNumberMap.put(dealerRecord.Account_Number__c, dealerRecord);
                    } else {
                        importedDealerAccountNumberNullMap.put(insertedId, dealerRecord);
                        nullAccountNumberData.add(dealerRecord);
                    }
                    importedInvoiceNumberMap.put(dealerRecord.Invoice_Number__c, dealerRecord);
                } else {
                    failedRecords.add(dealerRecord);
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug('Insert Failed: ' + dealerRecord + ' | Error: ' + err.getMessage());
                    }
                }
            }
        }
        Map<String, String> InsertedVendorDealerAccountKeyMap = new Map<String, String>();
        Map<String, Dealer_Import_Data__c> InsertedDealerAccountNumberDataMap = new Map<String, Dealer_Import_Data__c>();
        Set<String> importedProductSKUs = new Set<String>();
        if (!insertedRecordIds.isEmpty()) {
            for (Dealer_Import_Data__c dealerImportData : [
                SELECT Id, Dealer_Name__c, Vendor__r.Name,Account_Number__c,Product_SKU__c FROM Dealer_Import_Data__c WHERE Id IN : insertedRecordIds
            ]) {
                if (!String.isBlank(dealerImportData.Product_SKU__c)) {
                    importedProductSKUs.add(dealerImportData.Product_SKU__c);
                }
                String key = dealerImportData.Vendor__r.Name+''+dealerImportData.Dealer_Name__c;
                InsertedVendorDealerAccountKeyMap.put(dealerImportData.Account_Number__c, key);
                InsertedDealerAccountNumberDataMap.Put(dealerImportData.Account_Number__c,dealerImportData);
            }
        }
        Map<String, Product2> existingProductsMap = new Map<String, Product2>();
        Map<String, Account_Number__c> existingDealerAccountNumberMap = new Map<String, Account_Number__c>();
        Map<String, String> existingDealerJourneyAccountNumberKeyMap = new Map<String, String>();
        Map<String, Account_Number__c> existingDealerAliasMap = new Map<String, Account_Number__c>();
        Map<String, Account_Number__c> existingDealerjourneyMap = new Map<String, Account_Number__c>();
        String ExistingVendorDealerJourneyKey;
        List<String> existingDealerJourneyIdList = new List<String>();
        List<Account_Number__c> accountNumbers = new List<Account_Number__c>();
        
        if (strVendorId != null) {
            for (Product2 prod : [SELECT Id, Name, StockKeepingUnit, Vendor__c FROM Product2 WHERE Vendor__c =: strVendorId]) {
                existingProductsMap.put(prod.StockKeepingUnit, prod);
            }
            accountNumbers = [SELECT Id, Name, Dealer__c, Dealer__r.Name, Account_Number__c, 
                              Vendor__c, Vendor__r.Name, Dealer_Journey__c, Active__c 
                              FROM Account_Number__c 
                              WHERE Vendor__c =: strVendorId 
                              AND Account_Number__c IN :importedDealerAccountNumberMap.keySet()];
            for (Account_Number__c curDealerAccountNumberDetails : accountNumbers) {
                existingDealerJourneyIdList.add(curDealerAccountNumberDetails.Dealer_Journey__c);
            }
        }
        List<Dealer_Journey__c> toUpdateDealerJourney = new List<Dealer_Journey__c>();
        
        if (!existingDealerJourneyIdList.isEmpty()) {
            for (Dealer_Journey__c curDealerJourney : [SELECT Id, RecordTypeId, Vendor__c, Dealer__c, Activation_Date__c, Active__c FROM Dealer_Journey__c WHERE Id IN :existingDealerJourneyIdList]) {
                if (curDealerJourney.RecordTypeId != recordTypeMap.get('Active') || !curDealerJourney.Active__c) {
                    curDealerJourney.RecordTypeId = recordTypeMap.get('Active');
                    curDealerJourney.Active__c = true;
                    curDealerJourney.Activation_Date__c = System.today();
                    toUpdateDealerJourney.add(curDealerJourney);
                }
            }
        }
        if (!toUpdateDealerJourney.isEmpty()) {
            update toUpdateDealerJourney;
        }
        accountNumbers = [SELECT Id, Name, Dealer__c, Dealer__r.Name, Account_Number__c,Vendor__c, Vendor__r.Name, Dealer_Journey__c, Active__c 
                          FROM Account_Number__c 
                          WHERE Vendor__c =: strVendorId 
                          AND Account_Number__c IN :importedDealerAccountNumberMap.keySet()];
        for (Account_Number__c curDealerAccountNumberDetails : accountNumbers) {
            existingDealerAccountNumberMap.put(curDealerAccountNumberDetails.Account_Number__c, curDealerAccountNumberDetails);
            existingDealerjourneyMap.Put(curDealerAccountNumberDetails.Dealer_Journey__c,curDealerAccountNumberDetails);
            ExistingVendorDealerJourneyKey = curDealerAccountNumberDetails.Dealer__r.Name + '' + curDealerAccountNumberDetails.Vendor__r.Name;
            existingDealerJourneyAccountNumberKeyMap.put(curDealerAccountNumberDetails.Account_Number__c, ExistingVendorDealerJourneyKey);
        }
        Map<String,Dealer_Journey_Alias__c> existingDealerJourneyAliasMap = new Map<String,Dealer_Journey_Alias__c>();
        List<Dealer_Import_Data__c> activeMatchedAccountNumberInputData = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> matchedAccountNumberInputData = new List<Dealer_Import_Data__c>();
        Map<String,Account_Number__c> matchedActiveAccountNumberMap = new Map<String,Account_Number__c>();
        Map<String,Account_Number__c> matchedInActiveAccountNumberMap = new Map<String,Account_Number__c>();
        Set<String> createNewAccountNumberSet = new Set<String>();
        Map<String,Account_Number__c> createNewDJAliasAccountNumberMap = new Map<String,Account_Number__c>();
        set<string> counterForAliasCreation = new set<String>();
        
        for(Dealer_Journey_Alias__c curDealerJourneyAlias : [select Id, Name, Dealer_Journey__c from Dealer_Journey_Alias__c]){
            existingDealerJourneyAliasMap.Put(curDealerJourneyAlias.Name , curDealerJourneyAlias);
        }
        /* if(existingDealerJourneyAccountNumberKeyMap.size()>0 && InsertedVendorDealerAccountKeyMap.size()>0){
for(string  importDealerAccountNumber : InsertedVendorDealerAccountKeyMap.keySet()){
// checking if the account number exists in the system
if(existingDealerJourneyAccountNumberKeyMap.containsKey(importDealerAccountNumber)){
matchedAccountNumberInputData.add(importedDealerAccountNumberMap.get(importDealerAccountNumber));
// checking if the account number matches with the vendor dealer key 
if(existingDealerJourneyAccountNumberKeyMap.get(importDealerAccountNumber) == InsertedVendorDealerAccountKeyMap.get(importDealerAccountNumber)){
// checking if the account number is active
if(existingDealerAccountNumberMap.get(importDealerAccountNumber).Active__c){
matchedActiveAccountNumberMap.Put(importDealerAccountNumber,existingDealerAccountNumberMap.get(importDealerAccountNumber));
}else if (!existingDealerAccountNumberMap.get(importDealerAccountNumber).Active__c){
matchedInActiveAccountNumberMap.Put(importDealerAccountNumber,existingDealerAccountNumberMap.get(importDealerAccountNumber));
}
// checking if the dealer journey alias exists in the system , if yes no action to be taken if not create a new journey alias.
}else if(existingDealerJourneyAliasMap.containsKey(InsertedDealerAccountNumberDataMap.get(importDealerAccountNumber).Dealer_Name__c)){
continue;
}else{
// as the csv file dealer name doesnt match with the existing dealer journey alias, we create a new dealer journey alias
createNewDJAliasAccountNumberMap.Put(importDealerAccountNumber,existingDealerAccountNumberMap.get(importDealerAccountNumber));
counterForAliasCreation.add(importDealerAccountNumber);
}
}else{
// account number dont match with existing account number for the imported data . these account numbers from the imported files will be marked skipped and processed in step 2
createNewAccountNumberSet.add(importDealerAccountNumber);
}
}
}*/
        if (!existingDealerJourneyAccountNumberKeyMap.isEmpty() && !InsertedVendorDealerAccountKeyMap.isEmpty()) {
            for (String importDealerAccountNumber : InsertedVendorDealerAccountKeyMap.keySet()) {
                
                // Check if the imported account number exists in the system
                if (existingDealerJourneyAccountNumberKeyMap.containsKey(importDealerAccountNumber)) {
                    matchedAccountNumberInputData.add(importedDealerAccountNumberMap.get(importDealerAccountNumber));
                    
                    // Fetch existing and imported vendor-dealer keys
                    String existingVendorDealerKey = existingDealerJourneyAccountNumberKeyMap.get(importDealerAccountNumber);
                    String importedVendorDealerKey = InsertedVendorDealerAccountKeyMap.get(importDealerAccountNumber);
                    
                    // Compare vendor-dealer keys
                    if (existingVendorDealerKey == importedVendorDealerKey) {
                        // Fetch account details safely
                        Account_Number__c existingAccount = existingDealerAccountNumberMap.get(importDealerAccountNumber);
                        
                        if (existingAccount != null) {
                            // Categorize as active or inactive
                            if (existingAccount.Active__c) {
                                matchedActiveAccountNumberMap.put(importDealerAccountNumber, existingAccount);
                            } else {
                                matchedInActiveAccountNumberMap.put(importDealerAccountNumber, existingAccount);
                            }
                        }
                    } else {
                        // Check if a dealer journey alias exists for the given dealer name
                        String dealerName = InsertedDealerAccountNumberDataMap.containsKey(importDealerAccountNumber) ? 
                            InsertedDealerAccountNumberDataMap.get(importDealerAccountNumber).Dealer_Name__c : null;
                        
                        if (dealerName == null || existingDealerJourneyAliasMap.containsKey(dealerName)) {
                            continue;  // No action needed if alias exists
                        }
                        
                        // If no matching dealer alias exists, create a new one
                        createNewDJAliasAccountNumberMap.put(importDealerAccountNumber, existingDealerAccountNumberMap.get(importDealerAccountNumber));
                        counterForAliasCreation.add(importDealerAccountNumber);
                    }
                } else {
                    // Imported account number does not exist in the system, mark for later processing
                    createNewAccountNumberSet.add(importDealerAccountNumber);
                }
            }
        }
                
        List<Dealer_Journey_Alias__c> toInsertList = new List<Dealer_Journey_Alias__c>();
        List<Dealer_Import_Data__c> skippedCreateNewDJAliasData = new List<Dealer_Import_Data__c>();
        if (!createNewDJAliasAccountNumberMap.isEmpty()) {
            for (Dealer_Import_Data__c dealerImportData : [SELECT Id, Dealer_Name__c, Account_Number__c, Data_Import_Status__c FROM Dealer_Import_Data__c
                                                           WHERE Account_Number__c IN : createNewDJAliasAccountNumberMap.keySet()
                                                          ]) {
                                                              String accountNumber = dealerImportData.Account_Number__c;
                                                              String dealerName = dealerImportData.Dealer_Name__c;
                                                              if(counterForAliasCreation.contains(dealerImportData.Account_Number__c)){
                                                                  counterForAliasCreation.remove(dealerImportData.Account_Number__c);
                                                                  Dealer_Journey_Alias__c curObj = new Dealer_Journey_Alias__c();
                                                                  curObj.Dealer_Journey__c = createNewDJAliasAccountNumberMap.get(accountNumber).Dealer_Journey__c;
                                                                  curObj.Name = dealerName;
                                                                  toInsertList.add(curObj);
                                                              }else {
                                                                  skippedCreateNewDJAliasData.add(dealerImportData);
                                                                  System.debug('Skipped dealer journey alias data. Current count: ' + skippedCreateNewDJAliasData.size());
                                                              }
                                                              
                                                          }
        } 
        
        if(!toInsertList.isEmpty()){
            try {
                insert toInsertList;
            } catch (DmlException e) {
                System.debug('Error inserting Dealer Journey Aliases: ' + e.getMessage());
            }
        }
        List<Dealer_Import_Data__c> toUpdateDealerImportDataStatus = new List<Dealer_Import_Data__c>();  
        try {
            for (Dealer_Import_Data__c dealerImportData : [SELECT Id, Dealer_Name__c, Invoice_Date__c, Invoice_Number__c, Product_SKU__c,Product_Quantity__c, Unit_Price__c, Commission_Received__c, 
                                                           Account_Number__c, Vendor__c, Data_Import_Status__c 
                                                           FROM Dealer_Import_Data__c 
                                                           WHERE Account_Number__c IN : createNewAccountNumberSet]) {
                                                               
                                                               dealerImportData.Data_Import_Status__c = 'Skipped';
                                                               toUpdateDealerImportDataStatus.add(dealerImportData);
                                                               
                                                               if (String.isNotBlank(dealerImportData.Product_SKU__c)) {
                                                                   importedDealerProductMap.remove(dealerImportData.Product_SKU__c);
                                                               }
                                                               if (String.isNotBlank(dealerImportData.Dealer_Name__c)) {
                                                                   importedDealerDataNameMap.remove(dealerImportData.Dealer_Name__c);
                                                               }
                                                               if (String.isNotBlank(dealerImportData.Account_Number__c)) {
                                                                   importedDealerAccountNumberMap.remove(dealerImportData.Account_Number__c);
                                                               }
                                                               if (String.isNotBlank(dealerImportData.Invoice_Number__c)) {
                                                                   importedInvoiceNumberMap.remove(dealerImportData.Invoice_Number__c);
                                                               }
                                                           }
            
            if (!toUpdateDealerImportDataStatus.isEmpty()) {
                update toUpdateDealerImportDataStatus;
            }
        } catch (DmlException e) {
            System.debug('Error updating Dealer Import Data: ' + e.getMessage());
        }

        List<Product2> newProductsToInsert = new List<Product2>();
        for (String sku : importedProductSKUs) {
            if (!existingProductsMap.containsKey(sku)) {
                Product2 newProduct = new Product2(
                    Name = sku,
                    StockKeepingUnit = sku,
                    Vendor__c = strVendorId
                );
                newProductsToInsert.add(newProduct);
            }
        }
        if (!newProductsToInsert.isEmpty()) {
            insert newProductsToInsert;
            for (Product2 newProduct : newProductsToInsert) {
                existingProductsMap.put(newProduct.StockKeepingUnit, newProduct);
            }
        }
        Map<String, Product2> updatedProductMap = new Map<String, Product2>();
        
        List<Product2> relevantProducts = [SELECT Id, Name, StockKeepingUnit FROM Product2 WHERE StockKeepingUnit IN :importedProductSKUs];
        
        for (Product2 product : relevantProducts) {
            if (String.isNotBlank(product.StockKeepingUnit)) {
                updatedProductMap.put(product.StockKeepingUnit, product);
            }
        }
        Map<String, Dealer_Invoice__c> systemInvoiceNumberMap = new Map<String, Dealer_Invoice__c>();
        
        if (!importedInvoiceNumberMap.isEmpty()) {
            for (Dealer_Invoice__c invoice : [
                SELECT Id, Invoice_Number__c FROM Dealer_Invoice__c 
                WHERE Invoice_Number__c IN : importedInvoiceNumberMap.keySet()
            ]) {
                systemInvoiceNumberMap.put(invoice.Invoice_Number__c, invoice);
            }
        }
        List<Dealer_Invoice__c> toInsertInvoiceData = new List<Dealer_Invoice__c>();
        Set<String> newInvoiceNumbers = new Set<String>();
        
        for (Dealer_Import_Data__c curInputData : importedInvoiceNumberMap.values()) {
            if (!systemInvoiceNumberMap.containsKey(curInputData.Invoice_Number__c)) {
                Dealer_Invoice__c newInvoice = new Dealer_Invoice__c(
                    Invoice_Date__c = curInputData.Invoice_Date__c,
                    Invoice_Number__c = curInputData.Invoice_Number__c,
                    Dealer__c = existingDealerAccountNumberMap.get(curInputData.Account_Number__c)?.Dealer__c,
                    Vendor__c = strVendorId
                );
                toInsertInvoiceData.add(newInvoice);
                newInvoiceNumbers.add(curInputData.Invoice_Number__c);
            }
        }
        if (!toInsertInvoiceData.isEmpty()) {
            Database.SaveResult[] invoiceResults = Database.insert(toInsertInvoiceData, false);
            
            for (Integer i = 0; i < invoiceResults.size(); i++) {
                if (invoiceResults[i].isSuccess()) {
                    Dealer_Invoice__c insertedInvoice = toInsertInvoiceData[i];
                    systemInvoiceNumberMap.put(insertedInvoice.Invoice_Number__c, insertedInvoice);
                    
                }
            }
        }
        List<Dealer_Invoice_Line__c> invoiceDetailLinetItemInsertList = new List<Dealer_Invoice_Line__c>();
        
        for (Dealer_Import_Data__c curInputData : importedDataList) {
            if (systemInvoiceNumberMap.containsKey(curInputData.Invoice_Number__c)) {
                invoiceDetailLinetItemInsertList.add(new Dealer_Invoice_Line__c(
                    Dealer_Invoice__c = systemInvoiceNumberMap.get(curInputData.Invoice_Number__c).Id,
                    Invoice_Date__c = curInputData.Invoice_Date__c,
                    Invoice_Number__c = curInputData.Invoice_Number__c,
                    Quantity__c = curInputData.Product_Quantity__c,
                    Product__c = updatedProductMap.get(curInputData.Product_SKU__c)?.Id,
                    Amount_Each__c = curInputData.Unit_Price__c,
                    Commission_Amount_Each__c = curInputData.Commission_Received__c
                ));
            }
        }
        Database.SaveResult[] lineItemResults = Database.insert(invoiceDetailLinetItemInsertList, false);
        Set<String> successfullyProcessedInvoiceNumbers = new Set<String>();
        
        for (Integer i = 0; i < lineItemResults.size(); i++) {
            if (lineItemResults[i].isSuccess()) {
                successfullyProcessedInvoiceNumbers.add(invoiceDetailLinetItemInsertList[i].Invoice_Number__c);
            }
        }
        if (!successfullyProcessedInvoiceNumbers.isEmpty()) {
            List<Dealer_Import_Data__c> toUpdateImportStatusList = new List<Dealer_Import_Data__c>();
            
            for (Dealer_Import_Data__c importData : [SELECT Id, Data_Import_Status__c, Invoice_Number__c 
                                                     FROM Dealer_Import_Data__c 
                                                     WHERE Invoice_Number__c IN :successfullyProcessedInvoiceNumbers]) {
                                                         importData.Data_Import_Status__c = 'Processed';
                                                         toUpdateImportStatusList.add(importData);
                                                     }
            
            if (!toUpdateImportStatusList.isEmpty()) {
                Database.update(toUpdateImportStatusList, false);
            }
        }
    }  
    public void finish(Database.BatchableContext BC) {
        Integer totalRecordsProcessed = [
            SELECT COUNT() FROM Dealer_Import_Data__c WHERE Batch_Import_Id__c = :batchImportId
        ];
        
        Integer totalInvoicesInserted = [
            SELECT COUNT() FROM Dealer_Invoice__c WHERE CreatedDate = TODAY
        ];
        
        Integer totalInvoiceLinesInserted = [
            SELECT COUNT() FROM Dealer_Invoice_Line__c WHERE CreatedDate = TODAY
        ];
    }
    
    public static List<String> parseCSVLine(String line) {
        List<String> values = new List<String>();
        Boolean insideQuote = false;
        String currentValue = '';
        
        for (Integer i = 0; i < line.length(); i++) {
            String ch = line.substring(i, i + 1);
            
            if (ch == '"') {
                if (insideQuote && i + 1 < line.length() && line.substring(i + 1, i + 2) == '"') {
                    currentValue += '"';
                    i++;
                } else {
                    insideQuote = !insideQuote;
                }
            } else if (ch == ',' && !insideQuote) {
                values.add(currentValue.trim());
                currentValue = '';
            } else {
                currentValue += ch;
            }
        }
        
        values.add(currentValue.trim());
        return values;
    }
    private static Date parseDate(String dateStr) {
        if (String.isBlank(dateStr)) {
            throw new IllegalArgumentException('Date cannot be blank.');
        }
        
        dateStr = dateStr.replace('/', '-').trim();
        List<String> possiblePatterns = new List<String>{'dd-MM-yyyy', 'MM-dd-yyyy', 'yyyy-MM-dd'};
            
            for (String pattern : possiblePatterns) {
                List<String> parts = dateStr.split('-');
                
                if (parts.size() == 3) {
                    try {
                        Integer day, month, year;
                        
                        if (pattern == 'dd-MM-yyyy') {
                            day = Integer.valueOf(parts[0]);
                            month = Integer.valueOf(parts[1]);
                            year = Integer.valueOf(parts[2]);
                        } else if (pattern == 'MM-dd-yyyy') {
                            month = Integer.valueOf(parts[0]);
                            day = Integer.valueOf(parts[1]);
                            year = Integer.valueOf(parts[2]);
                        } else { // yyyy-MM-dd
                            year = Integer.valueOf(parts[0]);
                            month = Integer.valueOf(parts[1]);
                            day = Integer.valueOf(parts[2]);
                        }
                        
                        return Date.newInstance(year, month, day);
                    } catch (Exception e) {
                        throw new IllegalArgumentException('Invalid date format for: ' + dateStr + '. Expected format: YYYY-MM-DD, DD-MM-YYYY, or MM-DD-YYYY.');
                    }
                }
            }
        
        throw new IllegalArgumentException('Unrecognized date format: ' + dateStr);
    }
    
    private static Integer safeInteger(String value) {
        try {
            return Integer.valueOf(value.replace(',', '').trim());
        } catch (Exception e) {
            System.debug('Integer Conversion Failed for: ' + value);
            return 0;
        }
    }
    
    private static Decimal safeDecimal(String value) {
        if (String.isBlank(value)) return 0.0;
        
        String cleanedValue = '';
        for (Integer i = 0; i < value.length(); i++) {
            String ch = value.substring(i, i + 1);
            if ((ch >= '0' && ch <= '9') || ch == '.') {
                cleanedValue += ch;
            }
        }
        
        try {
            return Decimal.valueOf(cleanedValue);
        } catch (Exception e) {
            return 0.0;
        }
    }
    
}