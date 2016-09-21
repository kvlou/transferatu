require "spec_helper"

describe Transferatu::Mediators::Groups::Purger do
  let(:group) { create(:group, deleted_at: Time.now) }

  let(:aws_key_id) { 'my-key-id' }
  let(:aws_secret) { 'my-key-secret' }
  let(:s3_client)  { double(:s3_client) }

  before do
    allow(Config).to receive(:aws_access_key_id).and_return(aws_key_id)
    allow(Config).to receive(:aws_secret_access_key).and_return(aws_secret)
    allow(Aws::S3::Client).to receive(:new)
                               .with(access_key_id: aws_key_id,
                                     secret_access_key: aws_secret,
                                     region: 'us-east-1')
                               .and_return(s3_client)
    allow(s3_client).to receive(:delete_object)

    2.times { create(:transfer, group: group, to_type: 'pg_restore') }
    2.times { create(:transfer, group: group,
                     to_type: 'pg_restore', deleted_at: Time.now) }
    2.times { create(:transfer, group: group,
                     to_type: 'gof3r', deleted_at: Time.now) }
  end

  it "refuses to purge non-deleted groups" do
    group.update(deleted_at: nil)
    expect do
      Transferatu::Mediators::Groups::Purger.run(group: group)
    end.to raise_error(ArgumentError)
  end

  it "cancels any unfinished transfers" do
    group.transfers.all? do |t|
      expect(t.canceled_at).to be_nil
      expect(t.finished_at).to be_nil
    end
    Transferatu::Mediators::Groups::Purger.run(group: group)
    group.transfers.all? do |t|
      t.reload
      expect(t.canceled_at).to_not be_nil
      expect(t.finished_at).to_not be_nil
    end
  end

  it "flags all transfers as deleted" do
    Transferatu::Mediators::Groups::Purger.run(group: group)
    group.transfers.all? { |t| expect(t.deleted_at).to_not be_nil }
  end

  it "purges all purgeable transfers" do
    expect(Transferatu::Transfer.purgeable(deleted_before: Time.now).count)
      .to be > 0
    Transferatu::Mediators::Groups::Purger.run(group: group)
    expect(Transferatu::Transfer.purgeable(deleted_before: Time.now).count)
      .to eq 0
  end
end
