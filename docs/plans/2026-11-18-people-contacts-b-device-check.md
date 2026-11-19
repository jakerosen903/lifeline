# Device check: a person can be linked to a contact (PC-b)

Do these on a real iPhone with real contacts, because the simulator cannot show the system prompt for contacts, limited access or `ContactAccessButton`. Tick each item when it works.

- [ ] 1. Record a story with a new name that fits one contact. The landing shows the system prompt with the usage string. Allow full access. The chip reads "Assumed · new, from your contacts" and the person has the contact's picture.
- [ ] 2. Open a person with no contact. "Link to a contact" finds a contact by first name, by family name and by nickname.
- [ ] 3. "Change", then "Unlink". The person, the moments and the picture stay.
- [ ] 4. Change the contact's name and picture in the Contacts app. Open Lifeline again. The linked row shows the new name. The picture changes only when the first picture was the contact's copy.
- [ ] 5. Delete the contact in the Contacts app. The row reads "This contact is not in your contacts now". Nothing else is lost.
- [ ] 6. Add a contact with the name of a person on file. That person's page asks "Is this the same person?".
- [ ] 7. Set contacts to "Limited Access" in Settings. The search shows the button that shares one more contact, and one tap shares it.
- [ ] 8. Set contacts to "None" in Settings. People and guesses still work. A person's page shows "Allow contacts in Settings".
- [ ] 9. Make a backup, then restore it on this phone. The linked rows still resolve.
- [ ] 10. With the photo card build (PR #31): drag another photo in front of the contact's picture. It stays first after the next launch.
- [ ] 11. Largest text size and VoiceOver on the linked row, the suggestion card and the contact search.

## Also look at

- The contact row at the largest text size, and its order in VoiceOver. Nobody has checked these by hand.
- The "Change" menu: "Link to another contact" and "Unlink".
- Real contact pictures in PNG and HEIC format. The tests use generated JPEG pictures.

## If an item fails

Report the item number and what you saw to the builder session. When a PR exists, report it in the PR.
