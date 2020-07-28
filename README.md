# Email Service Accelerator

## Email Service handler
The handler follow those steps:
- Finding the corresponding Contact from sender (can be null)
- Getting the thread id from the email (if any)
- Search or create the case in SF
- Extract, filter and insert attachment in SF
- Creation of the Email MEssage associated with the case
- Associate the images to the email message

## ThreadId on Case
On Case, we create a custom field which is indexed that represent the ThreadId.
The value (including the case id and the org id) is populated via a trigger.
This is needed to handled replies from customer on a case.

## Bad checksums
A list of bad checksum (MD5/Hex) are maintained to filter attachments.

## Deduplication
In case an image has a godd checksum but already in the database, we reuse the existing one.
