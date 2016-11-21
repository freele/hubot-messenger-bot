{Robot, Adapter, TextMessage} = require "hubot"

class Messenger extends Adapter
    constructor: (@robot) ->
        super @robot
        @verifyToken = process.env.MESSENGER_VERIFY_TOKEN
        @accessToken = process.env.MESSENGER_ACCESS_TOKEN
        @apiURL = "https://graph.facebook.com/v2.6"
        @robot.logger.info "hubot-messenger-bot: Adapter loaded."

    _subscribe: ->
        subscribeURL = "#{@apiURL}/me/subscribed_apps?access_token=#{@accessToken}"
        @robot.http(subscribeURL)
            .post() (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error subscribing app to page - #{body} #{httpRes.statusCode} (#{err})"
                @robot.logger.info "hubot-messenger-bot: Subscribed app to page.", body

    _createUser: (userId, roomId, cb) ->
        profileURL = "#{@apiURL}/#{userId}?fields=first_name,last_name&access_token=#{@accessToken}"
        @robot.http(profileURL)
            .get() (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error getting profile - #{body} #{httpRes.statusCode} (#{err})"
                _user = JSON.parse(body)
                _userName = "#{_user.first_name} #{_user.last_name}"
                cb @robot.brain.userForId(userId, name: _userName, room: roomId)

    _processMsg: (msg) ->
        if msg.message
            return unless (msg.message.text? || msg.message.attachments?)
        if msg.postback
            return unless (msg.postback.payload?)
        # console.log('msg keys', Object.keys(msg));
        # console.log('message.keys', msg.message && Object.keys(msg.message));
        # console.log('postback keys', msg.postback && Object.keys(msg.postback));
        # console.log('sender_action keys', msg.sender_action && Object.keys(msg.sender_action));
        # if msg.message
        #     console.log('quick_reply', msg.message.quick_reply && JSON.stringify(msg.message.quick_reply, null, 4));

        if msg.message
            _text = msg.message.text || JSON.stringify(msg.message.attachments)
            _mid = msg.message.mid
            # console.log('_mid', _mid);
        if msg.postback
            _text = JSON.stringify(msg.postback.payload)
            _mid = ''
        if msg.message
            if msg.message.quick_reply
                _text = JSON.stringify(msg.message.quick_reply.payload)
                _mid = ''

        _sender = msg.sender.id
        _recipient = msg.recipient.id
        @_createUser _sender, _recipient, (user) =>
            message = new TextMessage user, _text.trim(), _mid
            @receive(message) if message?

    _sendMsg: (context, msg) ->
        if typeof msg == 'string'
            # Facebook Messenger Platform only allows up to 320 characters
            # Use a plugin like https://github.com/ClaudeBot/hubot-longtext
            # to handle long messages...
            message = {
                text: msg.substring(0, 320)
            }
        else if typeof msg == 'object'
            message = msg

        apiUrl = "#{@apiURL}/me/messages?access_token=#{@accessToken}"

        if msg.sender_action
            data = JSON.stringify({
                recipient:
                    id: context.user.id
                sender_action: msg.sender_action
            })
        else if msg.setting_type == 'call_to_actions'
            console.log('SEND CALL TO ACTIONS')
            console.log('msg keys', Object.keys(msg));
            # msg.recipient = { id: context.user.id }
            data = JSON.stringify(msg)
            apiUrl = "#{@apiURL}/me/thread_settings?access_token=#{@accessToken}"
        else
            data = JSON.stringify({
                recipient:
                    id: context.user.id
                message
            })

        console.log('DATA', data);
        @robot.http(apiUrl)
            .header('Content-Type', 'application/json')
            .post(data) (err, httpRes, body) =>
                if err or httpRes.statusCode isnt 200
                    return @robot.logger.error "hubot-messenger-bot: error sending message - #{body} #{httpRes.statusCode} (#{err})"

    send: (envelope, strings...) ->
        if typeof strings[0] == 'string'
            @_sendMsg envelope, strings.join "\n"
        else if typeof strings[0] == 'object'
            @_sendMsg envelope, strings[0]

    reply: (envelope, strings...) ->
        @_sendMsg envelope, envelope.user.name + ": " + strings.join "\n #{envelope.user.name}: "

    run: ->
        unless @verifyToken
            @emit "error", new Error "You must configure the MESSENGER_VERIFY_TOKEN environment variable."
        unless @accessToken
            @emit "error", new Error "You must configure the MESSENGER_ACCESS_TOKEN environment variable."

        @robot.router.get "/webhook/", (req, res) =>
            if req.query["hub.verify_token"] is @verifyToken
              res.send req.query["hub.challenge"]
              # @_subscribe()
              return
            @robot.logger.warning "hubot-messenger-bot: Wrong validation token."
            res.send "Error, wrong validation token"

        @robot.router.post "/webhook/", (req, res) =>
            msgEvents = req.body.entry[0].messaging
            for msgEvent in msgEvents
                @_processMsg msgEvent

            res.send 200

        @robot.logger.info "hubot-messenger-bot: Adapter running."
        @emit "connected"

exports.use = (robot) ->
    new Messenger robot
