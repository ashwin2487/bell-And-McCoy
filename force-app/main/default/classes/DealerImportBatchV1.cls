global class DealerImportBatchV1 implements Database.Batchable<Dealer_Import_Data__c>, Database.Stateful {
    
    @TestVisible private Id importRecordId;
    @TestVisible private Integer batchSize;
    @TestVisible private Id strVendorId;
    @TestVisible private List<Product2> failedProducts = new List<Product2>();
    @TestVisible private Map<Product2, String> failedProductErrors = new Map<Product2, String>();
    
    public DealerImportBatchV1(Id importRecordId, Integer batchSize) {
        this.importRecordId = importRecordId;
        this.batchSize = batchSize;
    }
    global Iterable<Dealer_Import_Data__c> start(Database.BatchableContext BC) {
        return [
            SELECT Id, Dealer_Name__c, Invoice_Date__c, Invoice_Number__c,
            Product_SKU__c, Product_Quantity__c, Unit_Price__c, 
            Commission_Received__c, Account_Number__c, PO_Number__c,
            Job_Name__c, Project__c, Data_Import_Status__c, Line_Number__c, vendor__c
            FROM Dealer_Import_Data__c
            WHERE Import__c = :importRecordId
            AND Data_Import_Status__c = 'Inserted'
        ];
    }
    
    global void execute(Database.BatchableContext BC, List<Dealer_Import_Data__c> dealerRecordsList) {
        String batchJobId = BC.getJobId();
        
        Map<String, Id> recordTypeMap = new Map<String, Id>();
        for (RecordType rt : [
            SELECT Id, DeveloperName 
            FROM RecordType 
            WHERE SObjectType IN ('Account', 'Dealer_Journey__c', 'Import__c')
        ]) {
            recordTypeMap.put(rt.DeveloperName, rt.Id);
        }
        set<Id> batchDealerImportRecordIdSet = new Set<Id>();
        List<Dealer_Import_Data__c> importedDataList = new List<Dealer_Import_Data__c>();
        Map<String, List<Dealer_Import_Data__c>> importedDealerDataNameMap = new Map<String, List<Dealer_Import_Data__c>>();
        Map<String, List<Dealer_Import_Data__c>> importedDealerProductMap = new Map<String, List<Dealer_Import_Data__c>>();
        Map<String, List<Dealer_Import_Data__c>> importedDealerAccountNumberMap = new Map<String, List<Dealer_Import_Data__c>>();
        Map<String, List<Dealer_Import_Data__c>> importedInvoiceNumberMap = new Map<String, List<Dealer_Import_Data__c>>();
        Set<Id> validAccountNumberRecordIds = new Set<Id>();
        List<Dealer_Import_Data__c> toUpdateAccountNumberDataList = new List<Dealer_Import_Data__c>();
        
        for (Dealer_Import_Data__c dealerRecord : dealerRecordsList) {
            strVendorId = dealerRecord.vendor__c;
            if (dealerRecord.Product_SKU__c != null) {
                if (!importedDealerProductMap.containsKey(dealerRecord.Product_SKU__c)) {
                    importedDealerProductMap.put(dealerRecord.Product_SKU__c, new List<Dealer_Import_Data__c>());
                }
                importedDealerProductMap.get(dealerRecord.Product_SKU__c).add(dealerRecord);
            }
            
            if (dealerRecord.Dealer_Name__c != null) {
                if (!importedDealerDataNameMap.containsKey(dealerRecord.Dealer_Name__c)) {
                    importedDealerDataNameMap.put(dealerRecord.Dealer_Name__c, new List<Dealer_Import_Data__c>());
                }
                importedDealerDataNameMap.get(dealerRecord.Dealer_Name__c).add(dealerRecord);
            }
            
            if (dealerRecord.Account_Number__c != null) {
                if (!importedDealerAccountNumberMap.containsKey(dealerRecord.Account_Number__c)) {
                    importedDealerAccountNumberMap.put(dealerRecord.Account_Number__c, new List<Dealer_Import_Data__c>());
                }
                importedDealerAccountNumberMap.get(dealerRecord.Account_Number__c).add(dealerRecord);
                validAccountNumberRecordIds.add(dealerRecord.Id);
            } else {
                dealerRecord.Data_Import_Status__c = 'Account Number - Null';
                toUpdateAccountNumberDataList.add(dealerRecord);
            }
            if (dealerRecord.Invoice_Number__c != null) {
                if (!importedInvoiceNumberMap.containsKey(dealerRecord.Invoice_Number__c)) {
                    importedInvoiceNumberMap.put(dealerRecord.Invoice_Number__c, new List<Dealer_Import_Data__c>());
                }
                importedInvoiceNumberMap.get(dealerRecord.Invoice_Number__c).add(dealerRecord);
            }
            
            importedDataList.add(dealerRecord);
            
        }
        
        if (!toUpdateAccountNumberDataList.isEmpty()) {
            update toUpdateAccountNumberDataList;
        } 
        
        Map<String, String> InsertedVendorDealerAccountKeyMap = new Map<String, String>();
        Map<String, Set<String>> InsertedDealerAccountNumberDataMap = new Map<String, Set<String>>();
        Set<String> importedProductSKUs = new Set<String>();
        
        if (!validAccountNumberRecordIds.isEmpty()) {
            for (Dealer_Import_Data__c dealerImportData : [
                SELECT Id, Dealer_Name__c, Vendor__r.Name, Account_Number__c, Product_SKU__c 
                FROM Dealer_Import_Data__c 
                WHERE Id IN : validAccountNumberRecordIds 
                AND Import__c =: importRecordId AND Data_Import_Status__c = 'Inserted'
            ]) {
                if (!String.isBlank(dealerImportData.Product_SKU__c)) {
                    importedProductSKUs.add(dealerImportData.Product_SKU__c);
                }
                String key = dealerImportData.Vendor__r.Name + '' + dealerImportData.Dealer_Name__c;
                InsertedVendorDealerAccountKeyMap.put(dealerImportData.Account_Number__c, key);
                
                if (!InsertedDealerAccountNumberDataMap.containsKey(dealerImportData.Account_Number__c)) {
                    InsertedDealerAccountNumberDataMap.put(dealerImportData.Account_Number__c, new Set<String>());
                }
                InsertedDealerAccountNumberDataMap.get(dealerImportData.Account_Number__c).add(dealerImportData.Dealer_Name__c);
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
                              AND Account_Number__c IN : InsertedVendorDealerAccountKeyMap.KeySet()];
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
                    curDealerJourney.Import__c = importRecordId;
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
                          AND Account_Number__c IN : InsertedVendorDealerAccountKeyMap.KeySet()];
        
        for (Account_Number__c curDealerAccountNumberDetails : accountNumbers) {
            existingDealerAccountNumberMap.put(curDealerAccountNumberDetails.Account_Number__c, curDealerAccountNumberDetails);
            existingDealerjourneyMap.Put(curDealerAccountNumberDetails.Dealer_Journey__c,curDealerAccountNumberDetails);
            ExistingVendorDealerJourneyKey = curDealerAccountNumberDetails.Vendor__r.Name + '' + curDealerAccountNumberDetails.Dealer__r.Name;
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
        List<Dealer_Import_Data__c> toUpdateDealerImportDataStatus = new List<Dealer_Import_Data__c>();  
        List<Dealer_Journey_Alias__c> toInsertList = new List<Dealer_Journey_Alias__c>();
        List<Dealer_Import_Data__c> skippedCreateNewDJAliasData = new List<Dealer_Import_Data__c>();        
        
        for(Dealer_Journey_Alias__c curDealerJourneyAlias : [select Id, Name, Dealer_Journey__c from Dealer_Journey_Alias__c where Vendor__c =: strVendorId]){
            existingDealerJourneyAliasMap.Put(curDealerJourneyAlias.Name , curDealerJourneyAlias);
        }
        
        if (!InsertedVendorDealerAccountKeyMap.isEmpty()) {
            for (String importDealerAccountNumber : InsertedVendorDealerAccountKeyMap.keySet()) {
                
                if (existingDealerJourneyAccountNumberKeyMap.containsKey(importDealerAccountNumber)) {
                    List<Dealer_Import_Data__c> importedRecords = importedDealerAccountNumberMap.get(importDealerAccountNumber);
                    if (importedRecords != null) {
                        matchedAccountNumberInputData.addAll(importedRecords);
                    }
                    
                    String existingVendorDealerKey = existingDealerJourneyAccountNumberKeyMap.get(importDealerAccountNumber);
                    String importedVendorDealerKey = InsertedVendorDealerAccountKeyMap.get(importDealerAccountNumber);
                    Set<String> importedDealerNames = InsertedDealerAccountNumberDataMap.get(importDealerAccountNumber);
                    
                    for (String importedDealerName : importedDealerNames) {
                        Boolean shouldCreateAlias = false;
                        
                        if (existingVendorDealerKey == importedVendorDealerKey) {
                            if (existingDealerJourneyAliasMap.containsKey(importedDealerName)) {
                                Dealer_Journey_Alias__c existingAlias = existingDealerJourneyAliasMap.get(importedDealerName);
                                if (existingAlias.Name != importedDealerName) {
                                    shouldCreateAlias = true;
                                } else {
                                    continue;
                                }
                            } else {
                                shouldCreateAlias = true;
                            }
                        } else {
                            if (existingDealerJourneyAliasMap.containsKey(importedDealerName)) {
                                Dealer_Journey_Alias__c existingAlias = existingDealerJourneyAliasMap.get(importedDealerName);
                                if (existingAlias.Name != importedDealerName) {
                                    shouldCreateAlias = true;
                                }
                            } else {
                                shouldCreateAlias = true;
                            }
                        }
                        
                        if (shouldCreateAlias) {
                            Account_Number__c matchedAccNum = existingDealerAccountNumberMap.get(importDealerAccountNumber);
                            if (matchedAccNum != null) {
                                createNewDJAliasAccountNumberMap.put(importDealerAccountNumber, matchedAccNum);
                                counterForAliasCreation.add(importedDealerName);
                            }
                        }
                    }
                } else {
                    createNewAccountNumberSet.add(importDealerAccountNumber);
                }
            }
        }
        
        
        if (!createNewDJAliasAccountNumberMap.isEmpty()) {
            for (Dealer_Import_Data__c dealerImportData : [
                SELECT Id, Dealer_Name__c , Invoice_Date__c ,Invoice_Number__c,Product_SKU__c,Product_Quantity__c,Unit_Price__c ,Commission_Received__c ,Account_Number__c,
                PO_Number__c ,Job_Name__c ,Project__c ,Import__c , Vendor__c ,Data_Import_Status__c ,Batch_Id__c
                FROM Dealer_Import_Data__c 
                WHERE Account_Number__c IN : createNewDJAliasAccountNumberMap.keySet() 
                AND Import__c = : importRecordId AND Id IN : validAccountNumberRecordIds
            ]) {
                String accountNumber = dealerImportData.Account_Number__c;
                String dealerName = dealerImportData.Dealer_Name__c;
                
                dealerImportData.Data_Import_Status__c = 'Dealer Alias - Created New';
                toUpdateDealerImportDataStatus.add(dealerImportData);
                
                if (counterForAliasCreation.contains(dealerName)) {
                    counterForAliasCreation.remove(dealerName);
                    
                    Dealer_Journey_Alias__c curObj = new Dealer_Journey_Alias__c();
                    curObj.Dealer_Journey__c = createNewDJAliasAccountNumberMap.get(accountNumber).Dealer_Journey__c;
                    curObj.Name = dealerName;
                    curObj.Vendor__c = strVendorId;
                    curObj.Import__c = importRecordId;
                    curObj.Batch_Id__c = batchJobId;
                    toInsertList.add(curObj);
                } else {
                    skippedCreateNewDJAliasData.add(dealerImportData);
                }
            }
        }
        
        Database.SaveResult[] dealerJourneyAliasResult = Database.insert(toInsertList, false);
        Set<String> successfullyProcessedAliasName = new Set<String>();
        for (Integer i = 0; i < dealerJourneyAliasResult.size(); i++) {
            if (dealerJourneyAliasResult[i].isSuccess()) {
                successfullyProcessedAliasName.add(toInsertList[i].Name);
            }
        }
        try {
            for (Dealer_Import_Data__c dealerImportData : [
                SELECT Id, Dealer_Name__c, Invoice_Date__c, Invoice_Number__c, Product_SKU__c, Product_Quantity__c,
                Unit_Price__c, Commission_Received__c, Account_Number__c, PO_Number__c, Job_Name__c,
                Project__c, Import__c, Vendor__c, Data_Import_Status__c, Batch_Id__c
                FROM Dealer_Import_Data__c
                WHERE Account_Number__c IN : createNewAccountNumberSet
                AND Import__c = :importRecordId AND ID IN : validAccountNumberRecordIds]) {
                    dealerImportData.Data_Import_Status__c = 'Account Number - Create New';
                    toUpdateDealerImportDataStatus.add(dealerImportData);
                    
                    if (String.isNotBlank(dealerImportData.Product_SKU__c)) {
                        importedDealerProductMap.remove(dealerImportData.Product_SKU__c);
                    }
                    
                    if (String.isNotBlank(dealerImportData.Dealer_Name__c)) {
                        importedDealerDataNameMap.remove(dealerImportData.Dealer_Name__c);
                    }
                    
                    if (String.isNotBlank(dealerImportData.Account_Number__c)) {
                        List<Dealer_Import_Data__c> relatedList = importedDealerAccountNumberMap.get(dealerImportData.Account_Number__c);
                        if (relatedList != null) {
                            Integer indexToRemove = relatedList.indexOf(dealerImportData);
                            if (indexToRemove != -1) {
                                relatedList.remove(indexToRemove);
                            }
                            if (relatedList.isEmpty()) {
                                importedDealerAccountNumberMap.remove(dealerImportData.Account_Number__c);
                            }
                        }
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
        
        Map<String, Id> invoiceNumberMap = new Map<String, Id>(); 
        Map<String, Id> newInvoiceNumberMap = new Map<String, Id>();
        Set<String> journeyIds = new Set<String>();
        Set<String> existingInvoiceNumbers = new Set<String>();
        Map<String, String> dealerNameToJourneyId = new Map<String, String>();
        Map<String, String> journeyToDealerMap = new Map<String, String>();
        List<Dealer_Import_Data__c> validRecords = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> skippedDealerDetailsForNotMatchingAlias = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> skippedDealerDetailsForNullAccNum = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> matchedNonNullAccountNumberRecords = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> nonMatchedNonNullAccountNumberRecords = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> exactMatchedRecordsWithBothAccNumAndDJ = new List<Dealer_Import_Data__c>();
        Set<String> productSKUs = new Set<String>();
        Map<String, Account_Number__c> accountNumberMap = new Map<String, Account_Number__c>();
        
        for (Dealer_Journey_Alias__c alias : [
            SELECT Id, Name, Dealer_Journey__c 
            FROM Dealer_Journey_Alias__c 
            WHERE vendor__c =: strVendorId
        ]) {
            dealerNameToJourneyId.put(alias.Name, alias.Dealer_Journey__c);
        }
        
        for (Account_Number__c accNumber : [
            SELECT Id, Account_Number__c, Dealer_Journey__c 
            FROM Account_Number__c 
            WHERE vendor__c =: strVendorId
        ]) {
            accountNumberMap.put(accNumber.Account_Number__c, accNumber);
        }
        
        List<Dealer_Import_Data__c> toBeProcessedRecordsFinally = [
            SELECT Id, Dealer_Name__c, Invoice_Date__c, Invoice_Number__c, Product_SKU__c, Product_Quantity__c,
            Unit_Price__c, Commission_Received__c, Account_Number__c, PO_Number__c, Job_Name__c,
            Project__c, Import__c, Vendor__c, Data_Import_Status__c, Batch_Id__c
            FROM Dealer_Import_Data__c
            WHERE Import__c = : importRecordId AND ID IN: validAccountNumberRecordIds AND (Data_Import_Status__c = 'Inserted' OR Data_Import_Status__c = 'Dealer Alias - Created New')];
        
        for (Dealer_Import_Data__c record : toBeProcessedRecordsFinally) {
            Boolean hasValidAlias = dealerNameToJourneyId.containsKey(record.Dealer_Name__c);
            
            if (record.Product_SKU__c != null) {
                productSKUs.add(record.Product_SKU__c.trim().toUpperCase());
            }
            
            if (record.Account_Number__c != null) {
                if (accountNumberMap.containsKey(record.Account_Number__c)) {
                    matchedNonNullAccountNumberRecords.add(record);
                    if (hasValidAlias) {
                        exactMatchedRecordsWithBothAccNumAndDJ.add(record);
                        existingInvoiceNumbers.add(record.Invoice_Number__c);
                        journeyIds.add(dealerNameToJourneyId.get(record.Dealer_Name__c));
                    } else {
                        skippedDealerDetailsForNotMatchingAlias.add(record);
                    }
                } else {
                    nonMatchedNonNullAccountNumberRecords.add(record);
                }
            } else {
                if (hasValidAlias) {
                    exactMatchedRecordsWithBothAccNumAndDJ.add(record);
                    existingInvoiceNumbers.add(record.Invoice_Number__c);
                    journeyIds.add(dealerNameToJourneyId.get(record.Dealer_Name__c));
                } else {
                    skippedDealerDetailsForNullAccNum.add(record);
                }
            }
        }
        
        Map<String, Product2> productSKUMap = new Map<String, Product2>();
        Map<String, Product2> productNameMap = new Map<String, Product2>();
        for (Product2 p : [
            SELECT Id, StockKeepingUnit, Name 
            FROM Product2 
            WHERE Vendor__c = :strVendorId
        ]) {
            if (p.StockKeepingUnit != null) {
                productSKUMap.put(p.StockKeepingUnit.trim().toUpperCase(), p);
            }
            if (p.Name != null) {
                productNameMap.put(p.Name.trim().toUpperCase(), p);
            }
        }
        
        List<Product2> newProducts = new List<Product2>();
        for (String rawSku : productSKUs) {
            String sku = rawSku != null ? rawSku.trim().toUpperCase() : '';
            if (!productSKUMap.containsKey(sku) && !productNameMap.containsKey(sku)) {
                newProducts.add(new Product2(
                    Name = sku,
                    StockKeepingUnit = sku,
                    Vendor__c = strVendorId,
                    Import__c = importRecordId,
                    Batch_Id__c = batchJobId
                ));
            }
        }
        
        if (!newProducts.isEmpty()) {
            Database.SaveResult[] productResults = Database.insert(newProducts, false);
            for (Integer i = 0; i < productResults.size(); i++) {
                if (productResults[i].isSuccess()) {
                    Product2 p = newProducts[i];
                    productSKUMap.put(p.StockKeepingUnit, p);
                } else {
                    Product2 failedProduct = newProducts[i];
                    String errorMessages = '';
                    for (Database.Error err : productResults[i].getErrors()) {
                        errorMessages += err.getMessage() + ' | ';
                        System.debug('Product Insert Failed: ' + failedProduct + ' | Error: ' + err.getMessage());
                    }
                    failedProducts.add(failedProduct);
                    failedProductErrors.put(failedProduct, errorMessages);
                }
            }
        }
        
        Id activeRTId = Schema.SObjectType.Dealer_Journey__c.getRecordTypeInfosByDeveloperName().get('Active').getRecordTypeId();
        List<Dealer_Journey__c> journeysToUpdate = new List<Dealer_Journey__c>();
        for (Dealer_Journey__c journey : [
            SELECT Id, RecordTypeId, Active__c 
            FROM Dealer_Journey__c 
            WHERE Id IN :journeyIds
        ]) {
            if (journey.RecordTypeId != activeRTId || !journey.Active__c) {
                journey.RecordTypeId = activeRTId;
                journey.Active__c = true;
                journey.Activation_Date__c = System.today();
                journeysToUpdate.add(journey);
            }
        }
        
        if (!journeysToUpdate.isEmpty()) update journeysToUpdate;
        
        for (Dealer_Journey__c j : [
            SELECT Id, Dealer__c 
            FROM Dealer_Journey__c 
            WHERE Id IN :journeyIds
        ]) {
            journeyToDealerMap.put(j.Id, j.Dealer__c);
        }
        
        for (Dealer_Invoice__c inv : [
            SELECT Id, Invoice_Number__c 
            FROM Dealer_Invoice__c 
            WHERE Invoice_Number__c IN :existingInvoiceNumbers AND Vendor__c = :strVendorId
        ]) {
            String normalizedInvoiceNumber = inv.Invoice_Number__c.trim().toUpperCase();
            invoiceNumberMap.put(normalizedInvoiceNumber, inv.Id);
        }
        
        List<Dealer_Invoice_Line__c> lineItems = new List<Dealer_Invoice_Line__c>();
        Map<String, Dealer_Invoice__c> newInvoicesMap = new Map<String, Dealer_Invoice__c>();
        system.debug('to be processes records finally '+toBeProcessedRecordsFinally);
        for (Dealer_Import_Data__c record : toBeProcessedRecordsFinally) {
            String normalizedInvoiceNumber = record.Invoice_Number__c.trim().toUpperCase();
            Id invoiceId = invoiceNumberMap.containsKey(normalizedInvoiceNumber)
                ? invoiceNumberMap.get(normalizedInvoiceNumber)
                : null;
            
            String normalizedSKU = record.Product_SKU__c.trim().toUpperCase();
            Id productId = productSKUMap.containsKey(normalizedSKU)
                ? productSKUMap.get(normalizedSKU).Id
                : null;
            
            if (invoiceId != null) {
                lineItems.add(new Dealer_Invoice_Line__c(
                    Dealer_Invoice__c = invoiceId,
                    Invoice_Date__c = record.Invoice_Date__c,
                    Invoice_Number__c = record.Invoice_Number__c,
                    Quantity__c = record.Product_Quantity__c,
                    Product__c = productId,
                    Amount_Each__c = record.Unit_Price__c,
                    Commission_Amount_Each__c = record.Commission_Received__c,
                    Import__c = importRecordId,
                    Batch_Id__c = batchJobId
                ));
            } else {
                
                String dealerJourneyId = dealerNameToJourneyId.get(record.Dealer_Name__c);
                String dealerId = journeyToDealerMap.get(dealerJourneyId);
                Id accountId = record.Account_Number__c != null
                    ? accountNumberMap.get(record.Account_Number__c)?.Id
                    : null;
                
                if (dealerJourneyId != null && dealerId != null) {
                    Dealer_Invoice__c inv = new Dealer_Invoice__c(
                        Invoice_Date__c = record.Invoice_Date__c,
                        Invoice_Number__c = record.Invoice_Number__c,
                        Dealer__c = dealerId,
                        Vendor__c = strVendorId,
                        Import__c = importRecordId,
                        Dealer_Journey__c = dealerJourneyId,
                        PO_Number__c = record.PO_Number__c,
                        Job_Name__c = record.Job_Name__c,
                        Project__c = record.Project__c,
                        Batch_Id__c = batchJobId
                    );
                    
                    if (accountId != null) {
                        inv.Account_Number__c = accountId;
                    }
                    
                    newInvoicesMap.put(normalizedInvoiceNumber, inv);
                } else {
                    System.debug('Skipping record due to missing journey/dealer: ' + record);
                }
            }
        }
        
        if (!newInvoicesMap.isEmpty()) {
            insert newInvoicesMap.values();
            
            for (Dealer_Invoice__c inv : newInvoicesMap.values()) {
                String normalizedInvoiceNumber = inv.Invoice_Number__c.trim().toUpperCase();
                newInvoiceNumberMap.put(normalizedInvoiceNumber, inv.Id);
            }
        }
        
        for (Dealer_Import_Data__c record : toBeProcessedRecordsFinally) {
            String normalizedInvoiceNumber = record.Invoice_Number__c.trim().toUpperCase();
            
            if (newInvoiceNumberMap.containsKey(normalizedInvoiceNumber)) {
                Id invoiceId = newInvoiceNumberMap.get(normalizedInvoiceNumber);
                String normalizedSKU = record.Product_SKU__c.trim().toUpperCase();
                Id productId = productSKUMap.containsKey(normalizedSKU)
                    ? productSKUMap.get(normalizedSKU).Id
                    : null;
                
                lineItems.add(new Dealer_Invoice_Line__c(
                    Dealer_Invoice__c = invoiceId,
                    Invoice_Date__c = record.Invoice_Date__c,
                    Invoice_Number__c = record.Invoice_Number__c,
                    Quantity__c = record.Product_Quantity__c,
                    Product__c = productId,
                    Amount_Each__c = record.Unit_Price__c,
                    Commission_Amount_Each__c = record.Commission_Received__c,
                    Import__c = importRecordId,
                    Batch_Id__c = batchJobId
                ));
            }
        }
        
        if (!lineItems.isEmpty()) {
            insert lineItems;
        }
        
        List<Dealer_Import_Data__c> toUpdate = new List<Dealer_Import_Data__c>();
        
        List<Dealer_Import_Data__c> filteredSkippedDealerDetailsForNullAccNum = new List<Dealer_Import_Data__c>();
        List<Dealer_Import_Data__c> filteredSkippedDealerDetailsForNotMatchingAlias = new List<Dealer_Import_Data__c>();
        
        for (Dealer_Import_Data__c skippedDealer : skippedDealerDetailsForNullAccNum) {
            if (!invoiceNumberMap.containsKey(skippedDealer.Invoice_Number__c) && 
                !newInvoiceNumberMap.containsKey(skippedDealer.Invoice_Number__c)) {
                    filteredSkippedDealerDetailsForNullAccNum.add(skippedDealer);
                }
        }
        
        for (Dealer_Import_Data__c skippedDealer : skippedDealerDetailsForNotMatchingAlias) {
            if (!invoiceNumberMap.containsKey(skippedDealer.Invoice_Number__c) && 
                !newInvoiceNumberMap.containsKey(skippedDealer.Invoice_Number__c)) {
                    filteredSkippedDealerDetailsForNotMatchingAlias.add(skippedDealer);
                }
        }
        
        for (Dealer_Import_Data__c record : toBeProcessedRecordsFinally) {
            if (invoiceNumberMap.containsKey(record.Invoice_Number__c) || newInvoiceNumberMap.containsKey(record.Invoice_Number__c)) {
                record.Data_Import_Status__c = 'Processed';
                record.Batch_Id__c = batchJobId;
                toUpdate.add(record);
            }
        }
        
        for (Dealer_Import_Data__c skippedDealer : filteredSkippedDealerDetailsForNullAccNum) {
            skippedDealer.Data_Import_Status__c = 'Account Number - Null';
            skippedDealer.Batch_Id__c = batchJobId;
            toUpdate.add(skippedDealer);
        }
        
        for (Dealer_Import_Data__c skippedDealer : filteredSkippedDealerDetailsForNotMatchingAlias) {
            skippedDealer.Data_Import_Status__c = 'Dealer Alias - Created New';
            skippedDealer.Batch_Id__c = batchJobId;
            toUpdate.add(skippedDealer);
        }
        
        if (!toUpdate.isEmpty()) {
            update toUpdate;
        }
    }    
    global void finish(Database.BatchableContext BC) {
        try {
            String batchJobId = BC.getJobId();
            
            Import__c importRec = [
                SELECT Id, Vendor__r.Name
                FROM Import__c
                WHERE Id = :importRecordId
                LIMIT 1
            ];
            
            String vendorName = importRec.Vendor__r.Name;
            
            Integer totalRecordsProcessed = [
                SELECT COUNT() 
                FROM Dealer_Import_Data__c
                WHERE Import__c = :importRecordId 
                AND Batch_Id__c = :batchJobId
                AND (Data_Import_Status__c = 'Processed' OR Data_Import_Status__c = 'Dealer Alias - Created New')
            ];
            
            Integer totalInvoicesInserted = [
                SELECT COUNT()
                FROM Dealer_Invoice__c
                WHERE Import__c = :importRecordId AND Batch_Id__c = :batchJobId
            ];
            
            Integer totalInvoiceLinesInserted = [
                SELECT COUNT()
                FROM Dealer_Invoice_Line__c
                WHERE Import__c = :importRecordId AND Batch_Id__c = :batchJobId
            ];
            
            Integer totalProductsInserted = [
                SELECT COUNT()
                FROM Product2
                WHERE Import__c = :importRecordId AND Batch_Id__c = :batchJobId
            ];
            
            insert new Batch_Process_Summary__c(
                Import_Record__c = importRecordId,
                Batch_Job_Id__c = batchJobId,
                Total_Records_Processed__c = totalRecordsProcessed,
                Total_Invoices_Inserted__c = totalInvoicesInserted,
                Total_Invoice_Lines_Inserted__c = totalInvoiceLinesInserted,
                Total_Products_Inserted__c = totalProductsInserted
            );
            
            String userEmail = [
                SELECT Email FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1
            ].Email;
            
            String emailBody = 'Dealer Import Records Batch Job Completed.\n\n'
                + 'Vendor: ' + vendorName + '\n'
                + 'Import Record ID: ' + importRecordId + '\n\n'
                + 'Total Dealer Import Records Processed: ' + totalRecordsProcessed + '\n'
                + 'Total Invoices Inserted: ' + totalInvoicesInserted + '\n'
                + 'Total Invoice Line Items Inserted: ' + totalInvoiceLinesInserted + '\n'
                + 'Total Products Inserted: ' + totalProductsInserted + '\n\n'
                + 'Job ID: ' + batchJobId + '\n'
                + 'Completed on: ' + System.now().format() + '\n';
            
            if (!failedProducts.isEmpty()) {
                emailBody += '\nFailed Product Insertions:\n\n';
                Integer counter = 1;
                for (Product2 failedProd : failedProducts) {
                    emailBody += '--- Failed Product ' + counter + ' ---\n'
                        + 'SKU: ' + failedProd.StockKeepingUnit + '\n'
                        + 'Name: ' + failedProd.Name + '\n'
                        + 'Error Message(s): ' + failedProductErrors.get(failedProd) + '\n\n';
                    counter++;
                }
            }
            
            Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
            mail.setToAddresses(new String[] { userEmail, 'cclarke@bellandmccoy.com' });
            mail.setSubject('Dealer Import Batch Summary for Vendor : ' + vendorName);
            mail.setPlainTextBody(emailBody);
            Messaging.sendEmail(new Messaging.SingleEmailMessage[] { mail });
            
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Error in finish method: ' + ex.getMessage());
        }
    }  
}