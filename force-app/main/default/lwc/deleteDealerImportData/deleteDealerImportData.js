import { LightningElement, api } from 'lwc';
import deleteImportDealerData from '@salesforce/apex/deleteRecordsController.deleteImportDealerData';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class DeleteDealerImportData extends LightningElement {
    isProcessing = false;
    @api recordId;

    handleProcess() {
        this.isProcessing = true;
        deleteImportDealerData({ importRecordId: this.recordId })
            .then(jobId => {
                this.showToast('Success', `Batch started. Job ID: ${jobId}`, 'success');
                // Optionally do something with jobId
                console.log('Batch Job ID:', jobId);
            })
            .catch(error => {
                this.showToast('Error', error.body?.message || 'An error occurred', 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}