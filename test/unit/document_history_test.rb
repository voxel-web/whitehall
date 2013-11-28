require 'test_helper'

class DocumentHistoryTest < ActiveSupport::TestCase
  test "#changes on the first public edition uses the edition's change note if present" do
    edition  = create(:published_edition, change_note: "Some changes")
    document = edition.document
    history  = DocumentHistory.new(document)

    assert_equal 1, history.size
    assert_equal edition.public_timestamp, history[0].public_timestamp
    assert_equal 'Some changes', history[0].note
  end

  test "#changes on the first public edition uses the default change note if the edition does not have one" do
    edition  = create(:published_edition, change_note: nil)
    document = edition.document
    history  = DocumentHistory.new(document)

    assert_equal 1, history.size
    assert_equal edition.public_timestamp, history[0].public_timestamp
    assert_equal 'First published.', history[0].note
  end

  test "#changes on the first public edition uses the first_published_at timestamp to account for discrepancies with public_timestamp" do
    edition  = create(:published_edition, first_published_at: 4.days.ago, minor_change: false)
    document = edition.document
    history  = DocumentHistory.new(document)

    assert_equal 1, history.size
    assert_equal 4.days.ago, history[0].public_timestamp
  end

  test "#changes returns change history for all historic editions, excluding those with minor changes" do
    original_edition = create(:superseded_edition, first_published_at: 3.days.ago, change_note: nil)
    document         = original_edition.document
    new_edition_1    = create(:superseded_edition, document: document, published_major_version: 2, published_minor_version: 0, major_change_published_at: 2.days.ago, change_note: "some changes")
    new_edition_2    = create(:published_edition,  document: document, published_major_version: 2, published_minor_version: 1, minor_change: true)
    new_edition_3    = create(:published_edition,  document: document, published_major_version: 3, published_minor_version: 0, major_change_published_at: 1.day.ago, change_note: "more changes")
    history          = DocumentHistory.new(document)

    assert_equal 3, history.size
    assert_equal "more changes", history[0].note
    assert_equal 1.days.ago, history[0].public_timestamp
    assert_equal "some changes", history[1].note
    assert_equal 2.days.ago, history[1].public_timestamp
    assert_equal "First published.", history[2].note
    assert_equal 3.days.ago, history[2].public_timestamp
  end

  test "the first historic edition is always included, even if it is a minor change (i.e. broken data)" do
    edition  = create(:published_edition, minor_change: true, change_note: nil)
    document = edition.document
    history  = DocumentHistory.new(document)

    assert_equal 1, history.size
    assert_equal edition.public_timestamp, history[0].public_timestamp
    assert_equal 'First published.', history[0].note
  end

  test "a document with no public editions returns an empty history" do
    draft_document = create(:draft_edition).document
    history        = DocumentHistory.new(draft_document)

    assert history.empty?
    assert_equal 0, history.size
  end

  test "#most_recent change returns the timestamp of the most recently published edition" do
    original_edition = create(:superseded_edition, first_published_at: 3.days.ago, change_note: nil)
    document         = original_edition.document
    new_edition_1    = create(:superseded_edition, document: document, published_major_version: 2, published_minor_version: 0, major_change_published_at: 2.days.ago, change_note: "some changes")
    new_edition_2    = create(:published_edition,  document: document, published_major_version: 3, published_minor_version: 0, major_change_published_at: 1.day.ago, change_note: "more changes")
    new_edition_2    = create(:published_edition,  document: document, published_major_version: 2, published_minor_version: 1, minor_change: true)
    history          = DocumentHistory.new(document)

    assert_equal 1.day.ago, history.most_recent_change
  end

  test '#newly_published? returns true when there has only been one published edition' do
    document  = create(:published_edition).document
    assert DocumentHistory.new(document).newly_published?

    create(:superseded_edition, document: document)
    refute DocumentHistory.new(document).newly_published?
  end
end
