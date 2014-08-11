clearance = require './index'
async = require 'async'

americano = require 'americano-cozy-pouchdb'
Contact = americano.getModel 'Contact',
    fn            : String
    n             : String
    _attachments  : (x) -> x
    datapoints    : (x) -> x

# find the cozy adapter
CozyAdapter = try require 'americano-cozy-pouchdb/node_modules/jugglingdb-pouchdb-adapter'
catch e then require 'jugglingdb-pouchdb-adapter'


module.exports = (options) ->

    out = {}

    mailSubject = options.mailSubject
    mailTemplate = options.mailTemplate

    # send a share mail
    sendMail = (doc, key, cb) ->
        rule = doc.clearance.filter((rule) -> rule.key is key)[0]

        doc.getPublicURL (err, url) =>
            return cb err if err

            url += '?key=' + rule.key

            emailOptions = {doc, url, rule}
            async.parallel [
                (cb) -> mailSubject emailOptions, cb
                (cb) -> mailTemplate emailOptions, cb
            ], (err, results) ->
                [subject, htmlContent] = results
                emailInfo =
                    to: rule.email
                    subject: subject
                    content: url
                    html: htmlContent

                CozyAdapter.sendMailFromUser emailInfo, cb

    # change the whole clearance object
    out.change = (req, res, next) ->
        {clearance} = req.body
        req.doc.updateAttributes clearance: clearance, (err) ->
            return next err if err
            res.send req.doc

    # send multiple mails
    # expect body = [<rule>]
    out.sendAll = (req, res, next) ->
        toSend = req.body
        sent = []
        async.each toSend, (rule, cb) ->
            sent.push rule.key
            sendMail req.doc, rule.key, cb
        , (err) ->
            return next err if err
            newClearance = req.doc.clearance.map (rule) ->
                rule.sent = true if rule.key in sent
                return rule

            req.doc.updateAttributes clearance: newClearance, (err) ->
                    return next err if err
                    res.send req.doc

    out.getEmailsFromContactFields =  (contact) ->
        emails = contact.datapoints?.filter (dp) -> dp.name is 'email'
        emails = emails.map (dp) -> dp.value
        emails

    # take directly full name or build it from the name field.
    out.getContactFullName = (contact) ->
        contact.fn or contact.n?.split(';')[0..1].join(' ')

    # contact list for autocomplete
    out.contactList = (req, res, next) ->
        Contact.request 'all', (err, contacts) ->
            return next err if err
            res.send contacts.map (contact) ->
                name = out.getContactFullName contact
                emails = out.getEmailsFromContactFields contact
                return simple =
                    id: contact.id
                    hasPicture: contact._attachments?.picture?
                    name: name or '?'
                    emails: emails or []

    out.contactPicture = (req, res, next) ->
        Contact.find req.params.contactid, (err, contact) ->
            return next err if err

            unless contact._attachments?.picture
                err = new Error('not found')
                err.status = 404
                return next err

            stream = contact.getFile 'picture', (err) ->
                return res.error 500, "File fetching failed.", err if err
            stream.pipe res

    return out
