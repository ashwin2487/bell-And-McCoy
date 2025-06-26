public class AccountNumberCleaningBatch implements Database.Batchable<SObject> {
    
    public Database.QueryLocator start(Database.BatchableContext BC) {
        return Database.getQueryLocator('SELECT Id, Dealer_Journey__c, Dealer__c, Dealer__r.Name, Vendor__c FROM Account_Number__c WHERE Dealer_Journey__c != null');
    }
    public void execute(Database.BatchableContext BC, List<SObject> scope) {
        Set<Id> dealerJourneyIds = new Set<Id>();
        Map<Id, Account_Number__c> accountNumberMap = new Map<Id, Account_Number__c>();
        
        for (Account_Number__c accNumber : (List<Account_Number__c>)scope) {
            if (accNumber.Dealer_Journey__c != null) {
                dealerJourneyIds.add(accNumber.Dealer_Journey__c);
                accountNumberMap.put(accNumber.Dealer_Journey__c, accNumber);
            }
        }
        
        if (dealerJourneyIds.isEmpty()) {
            return;
        }
        Set<Id> existingDealerJourneyIds = new Set<Id>();
        for (Dealer_Journey__c existingJourney : [SELECT Id FROM Dealer_Journey__c WHERE Id IN :dealerJourneyIds]) {
            existingDealerJourneyIds.add(existingJourney.Id);
        }
        Id activeRecordTypeId;
        for (RecordType rt : [SELECT Id FROM RecordType WHERE SObjectType = 'Dealer_Journey__c' AND DeveloperName = 'Active']) {
            activeRecordTypeId = rt.Id;
        }
        if (activeRecordTypeId == null) {
            System.debug('Error: Active record type not found for Dealer_Journey__c');
            return;
        }
        List<Dealer_Journey__c> newDealerJourneys = new List<Dealer_Journey__c>();
        Map<Id, Dealer_Journey__c> dealerJourneyToAccountMap = new Map<Id, Dealer_Journey__c>();
        
        for (Id dealerJourneyId : dealerJourneyIds) {
            if (!existingDealerJourneyIds.contains(dealerJourneyId)) {
                Account_Number__c accNumber = accountNumberMap.get(dealerJourneyId);
                Dealer_Journey__c newJourney = new Dealer_Journey__c(
                    RecordTypeId = activeRecordTypeId,
                    Active__c = true,
                    Activation_Date__c = System.today(),
                    Vendor__c = accNumber.Vendor__c, 
                    Dealer__c = accNumber.Dealer__c,
                    csv_file_dealer_name__c = accNumber.Dealer__r.Name
                );
                newDealerJourneys.add(newJourney);
                dealerJourneyToAccountMap.put(dealerJourneyId, newJourney);
            }
        }
        
        if (!newDealerJourneys.isEmpty()) {
            Database.SaveResult[] results = Database.insert(newDealerJourneys, false);
            
            List<Account_Number__c> accountsToUpdate = new List<Account_Number__c>();
            List<Dealer_Journey__c> failedJourneys = new List<Dealer_Journey__c>();
            
            List<Id> dealerJourneyIdList = new List<Id>(dealerJourneyToAccountMap.keySet());
            
            for (Integer i = 0; i < results.size(); i++) {
                if (results[i].isSuccess()) {
                    Id newDealerJourneyId = newDealerJourneys[i].Id;
                    Id oldDealerJourneyId = dealerJourneyIdList[i];
                    
                    Account_Number__c accToUpdate = accountNumberMap.get(oldDealerJourneyId);
                    accToUpdate.Dealer_Journey__c = newDealerJourneyId;
                    accountsToUpdate.add(accToUpdate);
                } else {
                    failedJourneys.add(newDealerJourneys[i]);
                    for (Database.Error err : results[i].getErrors()) {
                        System.debug('Insert Failed: ' + newDealerJourneys[i] + ' | Error: ' + err.getMessage());
                    }
                }
            }
            
            if (!accountsToUpdate.isEmpty()) {
                try {
                    update accountsToUpdate;
                    System.debug('Total updated Account Numbers : ' + accountsToUpdate.size());
                } catch (DmlException e) {
                    System.debug('Update Failed: ' + e.getMessage());
                }
            }
            
            if (!failedJourneys.isEmpty()) {
                System.debug('Total Failed Dealer Journeys: ' + failedJourneys.size());
            }
        }
    }
    
    public void finish(Database.BatchableContext BC) {
        System.debug('Batch Process Completed.');
    }
}