# frozen_string_literal: true

require_relative "../spec_data/model/post_repository"
require_relative "../spec_data/model/user_repository"
require_relative "../spec_data/model/comment_repository"
require_relative "../spec_data/model/account_repository"
require_relative "../spec_data/dummy_event_manager"

# Test both repositories and records
RSpec.describe Verse::Model::Repository::Base do
  before do
    Verse.start(:server, config_path: File.join(__dir__, "../spec_data/config.yml"))

    PostRepository.clear
    UserRepository.clear
    CommentRepository.clear
    AccountRepository.clear

    PostRepository.id_sequence = 0
    UserRepository.id_sequence = 100
    CommentRepository.id_sequence = 200
    AccountRepository.id_sequence = 300

    @auth_context = Verse::Spec::Auth::MockContext.new(["*.*.*"])

    # create data
    @users = UserRepository.new(@auth_context)
    @posts = PostRepository.new(@auth_context)
    @accounts = AccountRepository.new(@auth_context)
    @comments = CommentRepository.new(@auth_context)

    id_john = nil
    id_jane = nil

    @users.no_event{ |r|
      id_john = r.create(name: "John")
      id_jane = r.create(name: "Jane")
    }

    @accounts.no_event{ |r|
      r.create(
        user_id: id_john,
        email: "john@example.tld",
        status: :active
      )

      r.create(
        user_id: id_jane,
        email: "jane@example.tld",
        status: :inactive
      )
    }

    id_post1 = nil
    id_post2 = nil

    @posts.no_event{ |_r|
      id_post1 = @posts.create(title: "Hello", user_id: id_john)
      id_post2 = @posts.create(title: "World", user_id: id_jane)
    }

    @comments.no_event{ |r|
      r.create(post_id: id_post1, user_id: id_john, content: "Hello World")
      r.create(post_id: id_post1, user_id: id_jane, content: "Hello John!")
    }

    @comments.no_event{ |r|
      r.create(post_id: id_post2, user_id: id_john, content: "World Hello")
      r.create(post_id: id_post2, user_id: id_jane, content: "World John!")
    }
  end

  describe "#self.table" do
    it "should infer table name" do
      expect(UserRepository.table).to eq("users")
      expect(PostRepository.table).to eq("posts")
      expect(CommentRepository.table).to eq("comments")
      expect(AccountRepository.table).to eq("accounts")
    end

    it "can be overriden" do
      UserRepository.table "custom_users"
      expect(UserRepository.table).to eq("custom_users")
    end
  end

  describe "events emissions" do
    before :each do
      Verse.event_manager = DummyEventManager.new
    end

    after :each do
      Verse.event_manager = nil
    end

    it "emits events on create" do
      expect(Verse.event_manager).to receive(:publish).with("verse_spec.user.created", { args: [name: "Joe"], metadata: {}, resource_id: "103" })
      @users.create(name: "Joe")
    end

    it "emit events on update" do
      expect(Verse.event_manager).to receive(:publish).with("verse_spec.user.updated", { args: [{ name: "John Doe" }], metadata: {}, resource_id: "101" })
      @users.update(101, { name: "John Doe" })
    end

    it "doesn't emit event with block no_event" do
      expect(Verse.event_manager).not_to receive(:publish)
      @users.no_event{ |r| r.create(name: "Luis") }
    end
  end

  describe "#find_by" do
    it "can find user" do
      user = @users.find_by({ name: "John" })

      expect(user).to be_a(UserRecord)
      expect(user.name).to eq("John")
      expect(user.id).to eq(101)
    end

    it "can find using filter" do
      user = @users.find_by({ name__in: ["John", "Jane"] })

      expect(user).not_to be_nil
    end

    it "returns nil if not found" do
      user = @users.find_by({ name: "Not Found" })

      expect(user).to be_nil
    end

    it "can uses custom filter" do
      post = @posts.find_by({ user_name: "John" })
      expect(post).not_to be_nil

      post = @posts.find_by({ user_name: "Joe" })
      expect(post).to be_nil
    end
  end

  describe "#find_by!" do
    it "throws error if not found" do
      expect do
        @users.find_by!({ name: "Not Found" })
      end.to raise_error(Verse::Error::RecordNotFound)
    end
  end

  describe "#update" do
    it "can update user" do
      out = @users.update(101, { name: "John Doe" })

      expect(out).to be true

      user = @users.find_by({ id: 101 })

      expect(user).to be_a(UserRecord)
      expect(user.name).to eq("John Doe")
      expect(user.id).to eq(101)
    end

    it "returns false if not found" do
      out = @users.update(999, { name: "John Doe" })
      expect(out).to be false
    end
  end

  describe "#update!" do
    it "throws error if not found" do
      expect do
        @users.update!(999, { name: "John Doe" })
      end.to raise_error(Verse::Error::RecordNotFound)
    end
  end

  describe "#delete" do
    it "can delete user" do
      out = @users.delete(101)

      expect(out).to be true

      user = @users.find_by({ id: 1 })

      expect(user).to be_nil
    end

    it "returns false if not found" do
      out = @users.delete(999)
      expect(out).to be false
    end
  end

  describe "#delete!" do
    it "throws error if not found" do
      expect do
        @users.delete!(999)
      end.to raise_error(Verse::Error::RecordNotFound)
    end
  end

  describe "#index" do
    it "can index users" do
      users = @users.index({})

      expect(users).to be_a(Verse::Util::ArrayWithMetadata)
      expect(users.size).to eq(2)
      expect(users.first).to be_a(UserRecord)
    end

    it "can index using filter" do
      users = @users.index({ name__in: ["John", "Jane"] })

      expect(users.size).to eq(2)
    end

    it "can index using pagination" do
      users = @users.index({}, page: 1, items_per_page: 1)

      expect(users.size).to eq(1)
      expect(users.first.id).to eq(101)
    end

    it "can index using sort" do
      users = @users.index({}, sort: { name: :asc })

      expect(users.length).to eq(2)
      expect(users.first.id).to eq(102)
    end

    it "can index using include" do
      users = @users.index({}, included: ["account"])

      expect(users.length).to eq(2)
      expect(users.first.account).to be_a(AccountRecord)
    end

    it "can index using nested includes + has_many/has_one" do
      posts = @posts.index({}, included: ["user.account", "comments"])

      expect(posts.length).to eq(2)
      expect(posts.first.user).to be_a(UserRecord)
      expect(posts.first.comments).to be_a(Array)
      expect(posts.first.user.account).to be_a(AccountRecord)
      expect(posts.first.user.account.active?).to be true
    end

    it "can fetch included of type belongs_to" do
    end

    it "can index using include and filter" do
      users = @users.index({ name__in: ["John", "Jane"] }, included: ["account"])

      expect(users.length).to eq(2)
      expect(users.first.account).to be_a(AccountRecord)
    end
  end

  describe "encoders" do
    it "encode fields correctly" do
      email = AccountRepository.data.first[:email]
      expect(EmailEncoder.decode(email)).to eq("john@example.tld")
    end
  end
end
