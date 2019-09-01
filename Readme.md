Title:	Twilio SMS Notification Addon Documentation
Author:	Atlas Systems, Inc.
Date:	2015 May 
Comment:	Documentation for the Twilio SMS Notification addon 


Twilio SMS Notifications
========================

The Twilio SMS Notifications addon is a server addon that will use the Twilio API for sending SMS notifications. Please review the ILLiad documentation for configuring server addons to learn how to add this server addon.

Prerequisites
--------------
1.  ILLiad v8.6
2.  A Twilio account. Register at http://twilio.com.


Addon Settings
--------------

**AccountSID**

The Twilio Account SID provided in your Twilio account settings.

**AuthToken**
      
The Twilio AuthToken provided in your Twilio account Settings.

**FromNumber**

A Twilio phone number enabled for the type of message you wish to send. Only phone numbers or short codes purchased from Twilio work here

**ActiveNVTGC**
      
If shared server, a comma separated list of NVTGC's that use this addon for sending SMS notifications. This setting is ignored for single server instances.


Sending Notifications
---------------------
The Twilio SMS notifications addon will handle pending SMS notifications for the ActiveNVTGC's listed in the addon settings. The Twilio AccountSID, AuthToken, and FromNumber must be provided in the addon settings for the Twilio SMS Notifications addon to function properly. When a message is sent via the addon to Twilio it is typically queued for a short time before it is processed by the SMS carrier. At this time the SMS notification will remain in the Sending status since it has been marked as being queued by Twilio. When an item is marked as queued the Twilio unique message identifier is added as the note in the SMS Copies table. 

Some errors that are reported by Twilio will cause the addon to attempt to re-send the message. Specifically Twilio error codes 21611, 30001, and 14107 will all attempt to retry sending the message the next time pending notifications are handled by the addon. System Manager will typically allow a notification to be retried up to 5 times before it will ultimately fail.

Error 21611
:   This 'From' number has exceeded the maximum number of queued messages

Error 30001
:   Message Delivery - Queue overflow

Error 14107
:   Message rate limit exceeded

Checking Queued Notifications
-----------------------------
Since Twilio will not immediately send the SMS notification, the addon will check the status for notifications that have been queued by Twilio. The uniqe identifier is retrieved using the note from the SMS Copies table. During each check of sending notifications (every 2 minutes), the addon will check with Twilio to determine the status of the notification. 

Note: System Manager will update *Sending* notifications to a status of Failed if it remains at Sending for more than 24 hours past the date the notification was originally generated.



