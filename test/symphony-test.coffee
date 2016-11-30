#
#    Copyright 2016 Jon Freedman
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

assert = require('chai').assert
{TextListener} = require 'hubot'
Symphony = require '../src/symphony'
{V2Message} = require '../src/message'
NockServer = require './nock-server'
{FakeRobot} = require './fakes'

describe 'On-premise key manager / agent', () ->
  nock = null
  symphony = null

  beforeEach ->
    nock = new NockServer({host: 'https://foundation.symphony.com', kmHost: 'https://keymanager.notsymphony.com', agentHost: 'https://agent.alsonotsymphony.com'})
    symphony = new Symphony({
      host: 'foundation.symphony.com',
      privateKey: './test/resources/privateKey.pem',
      publicKey: './test/resources/publicKey.pem',
      passphrase: 'changeit',
      keyManagerHost: 'keymanager.notsymphony.com',
      agentHost: 'agent.alsonotsymphony.com'
    })

  afterEach ->
    nock.close()

  it 'should connect to separate key manager / agent url', () ->
    msg = { foo: 'bar' }
    symphony.echo(msg)
      .then (response) ->
        assert.deepEqual(msg, response)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")


describe 'REST API test suite', () ->
  nock = null
  symphony = null

  beforeEach ->
    nock = new NockServer({host: 'https://foundation.symphony.com'})
    symphony = new Symphony({
      host: 'foundation.symphony.com',
      privateKey: './test/resources/privateKey.pem',
      publicKey: './test/resources/publicKey.pem',
      passphrase: 'changeit'
    })

  afterEach ->
    nock.close()

  it 'echo should obtain session and key tokens and echo response', () ->
    msg = { foo: 'bar' }
    symphony.echo(msg)
      .then (response) ->
        assert.deepEqual(msg, response)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'whoAmI should get userId', () ->
    symphony.whoAmI()
      .then (response) ->
        assert.equal(nock.botUserId, response.userId)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'getUser by userId should expose user details', () ->
    symphony.getUser({userId: nock.realUserId})
      .then (response) ->
        assert.equal(nock.realUserId, response.id)
        assert.equal(nock.realUserName, response.username)
        assert.equal(nock.realUserEmail, response.emailAddress)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'getUser by email should expose user details', () ->
    symphony.getUser({emailAddress: nock.realUserEmail})
      .then (response) ->
        assert.equal(nock.realUserId, response.id)
        assert.equal(nock.realUserName, response.username)
        assert.equal(nock.realUserEmail, response.emailAddress)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'getUser by username should expose user details', () ->
    symphony.getUser({username: nock.realUserName})
      .then (response) ->
        assert.equal(nock.realUserId, response.id)
        assert.equal(nock.realUserName, response.username)
        assert.equal(nock.realUserEmail, response.emailAddress)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'getUser should fail if called with just a string arg', (done) ->
    symphony.getUser(nock.realUserId)
      .then (response) ->
        assert.fail(0, 1,"Expecting failure")
      .fail (error) ->
        done()
    return

  it 'sendMessage should obtain session and key tokens and get message ack', () ->
    msg = '<messageML>Testing 123...</messageML>'
    symphony.sendMessage(nock.streamId, msg, 'MESSAGEML')
      .then (response) ->
        assert.equal(msg, response.message)
        assert.equal(nock.botUserId, response.fromUserId)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'getMessages should get all messages', () ->
    msg = '<messageML>Yo!</messageML>'
    symphony.sendMessage(nock.streamId, msg, 'MESSAGEML')
      .then (response) ->
        assert.equal(msg, response.message)
        symphony.getMessages(nock.streamId, nock.firstMessageTimestamp)
      .then (response) ->
        assert.isAtLeast(response.length, 2)
        assert.isAtLeast((m for m in response when m.message is '<messageML>Hello World</messageML>').length, 1)
        assert.isAtLeast((m for m in response when m.message is msg).length, 1)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'createDatafeed should generate a datafeed id', () ->
    symphony.createDatafeed()
      .then (response) ->
        assert.equal(nock.datafeedId, response.id)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'readDatafeed should pull messages', () ->
    msg1 = '<messageML>foo</messageML>'
    msg2 = '<messageML>bar</messageML>'
    symphony.createDatafeed()
      .then (initialResponse) ->
        # ensure that any previous message state is drained
        symphony.readDatafeed(initialResponse.id)
        .then (response) ->
          symphony.sendMessage(nock.streamId, msg1, 'MESSAGEML')
        .then (response) ->
          assert.equal(msg1, response.message)
          symphony.readDatafeed(initialResponse.id)
        .then (response) ->
          assert.equal(1, response.length)
          assert.equal(msg1, response[0].message)
        .then (response) ->
          symphony.sendMessage(nock.streamId, msg2, 'MESSAGEML')
        .then (response) ->
          assert.equal(msg2, response.message)
          symphony.readDatafeed(initialResponse.id)
        .then (response) ->
          assert.equal(1, response.length)
          assert.equal(msg2, response[0].message)
      .fail (error) ->
        assert.fail(0, 1, "Failed with error #{error}")

  it 'readDatafeed should not fail if no messages are available', () ->
    symphony.createDatafeed()
      .then (initialResponse) ->
        # ensure that any previous message state is drained
        symphony.readDatafeed(initialResponse.id)
        .then (response) ->
          symphony.readDatafeed(initialResponse.id)
        .then (response) ->
          assert.isUndefined(response)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

  it 'createIM should generate a stream id', () ->
    symphony.createIM(nock.realUserId)
      .then (response) ->
        assert.equal(nock.streamId, response.id)
      .fail (error) ->
        assert.fail(0, 1,"Failed with error #{error}")

describe 'Object model test suite', () ->
  for text in ['<messageML>Hello World</messageML>', 'Hello World']
    it "parse a V2Message containing '#{text}'", () ->
      msg = {
        id: 'foobar'
        v2messageType: 'V2Message'
        streamId: 'baz'
        message: text
        fromUserId: 12345
      }
      user = {
        id: 12345
        name: 'johndoe'
        displayName: 'John Doe'
      }
      v2 = new V2Message(user, msg)
      assert.equal('Hello World', v2.text)
      assert.equal('foobar', v2.id)
      assert.equal(12345, v2.user.id)
      assert.equal('johndoe', v2.user.name)
      assert.equal('John Doe', v2.user.displayName)
      assert.equal('baz', v2.room)

  it 'regex test', (done) ->
    msg = {
      id: 'foobar'
      v2messageType: 'V2Message'
      streamId: 'baz'
      message: 'butler ping'
      fromUserId: 12345
    }
    user = {
      id: 12345
      name: 'johndoe'
      displayName: 'John Doe'
    }
    robot = new FakeRobot
    callback = (response) ->
      done()
    listener = new TextListener(robot, /^\s*[@]?butler[:,]?\s*(?:PING$)/i, {}, callback)
    listener.call new V2Message(user, msg)
