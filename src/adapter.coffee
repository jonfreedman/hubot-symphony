#
#    Copyright 2016 The Symphony Software Foundation
#
#    Licensed under the Apache License, Version 2.0 (the "License");
#    you may not use this file except in compliance with the License.
#    You may obtain a copy of the License at
#
#        http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#

{Adapter} = require 'hubot'

Symphony = require './symphony'
{V2Message} = require './message'

class SymphonyAdapter extends Adapter

  constructor: ->
    super
    throw new Error('HUBOT_SYMPHONY_HOST undefined') unless process.env.HUBOT_SYMPHONY_HOST
    throw new Error('HUBOT_SYMPHONY_PUBLIC_KEY undefined') unless process.env.HUBOT_SYMPHONY_PUBLIC_KEY
    throw new Error('HUBOT_SYMPHONY_PRIVATE_KEY undefined') unless process.env.HUBOT_SYMPHONY_PRIVATE_KEY
    throw new Error('HUBOT_SYMPHONY_PASSPHRASE undefined') unless process.env.HUBOT_SYMPHONY_PASSPHRASE

  send: (envelope, strings...) ->
    @robot.logger.debug "Send"
    for string in strings
      @symphony.sendMessage(envelope.room, string, 'TEXT')

  reply: (envelope, strings...) ->
    @robot.logger.debug "Reply"
    for string in strings
      @symphony.sendMessage(envelope.room, "<messageML><mention email='#{envelope.user.emailAddress}'/> #{string}</messageML>", 'MESSAGEML')

  run: =>
    @robot.logger.info "Initialising..."
    @symphony = new Symphony(process.env.HUBOT_SYMPHONY_HOST, process.env.HUBOT_SYMPHONY_PRIVATE_KEY, process.env.HUBOT_SYMPHONY_PUBLIC_KEY, process.env.HUBOT_SYMPHONY_PASSPHRASE)
    @symphony.whoAmI()
      .then (response) =>
        @robot.userId = response.userId
        @symphony.getUser(response.userId)
        .then (response) =>
          @robot.displayName = response.userAttributes?.displayName
          @robot.logger.info "Connected as #{response.userAttributes?.displayName} [#{response.userSystemInfo?.status}]"
      .fail (err) =>
        @robot.emit 'error', new Error("Unable to resolve identity: #{err}")
    hourlyRefresh = memoize @symphony.getUser, {maxAge: 3600000, length: 1}
    @userLookup = (userId) => hourlyRefresh userId
    @symphony.createDatafeed()
      .then (response) =>
        @robot.logger.info "Created datafeed: #{response.id}"
        this.on 'poll', @_pollDatafeed
        @emit 'connected'
        @robot.logger.debug "'connected' event emitted"
        @emit 'poll', response.id
        @robot.logger.debug "First 'poll' event emitted"
      .fail (err) =>
        @robot.emit 'error', new Error("Unable to create datafeed: #{err}")

  close: =>
    @robot.logger.debug 'Removing datafeed poller'
    this.removeListener 'poll', @_pollDatafeed

  _pollDatafeed: (id) =>
    # defer execution to ensure we don't go into an infinite polling loop
    process.nextTick =>
      @robot.logger.debug "Polling datafeed #{id}"
      @symphony.readDatafeed(id)
        .then (response) =>
          if response?
            @robot.logger.debug "Received #{response.length} datafeed messages"
            @_receiveMessage msg for msg in response when msg.v2messageType = 'V2Message'
          @emit 'poll', id
        .fail (err) =>
          @robot.emit 'error', new Error("Unable to read datafeed #{id}: #{err}")

  _receiveMessage: (message) =>
    @userLookup(message.fromUserId)
      .then (response) =>
        v2 = new V2Message(response, message)
        @robot.logger.debug "Received '#{v2.text}' from #{v2.user.name}"
        @robot.receive v2
      .fail (err) =>
        @robot.emit 'error', new Error("Unable to fetch user details: #{err}")

exports.use = (robot) ->
  new SymphonyAdapter robot