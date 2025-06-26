import { LightningElement, api } from 'lwc';
import processRecordsSkipped from '@salesforce/apex/SkippedRecordsController.processRecordsSkipped';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class ProcessSkippedRecords extends LightningElement {
    isProcessing = false;
    @api recordId;

    handleProcess() {
        this.isProcessing = true;
        processRecordsSkipped({ importRecordId: this.recordId })
            .then(result => {
                
                this.showToast('Success', result.message, 'success');
            })
            .catch(error => {
                
                this.showToast('Error', error.body?.message || 'An error occurred', 'error');
            })
            .finally(() => {
                this.isProcessing = false;
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title,
            message,
            variant
        });
        this.dispatchEvent(event);
    }
}