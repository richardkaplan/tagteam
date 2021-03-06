shared_examples 'a tag filter' do |filter_type|
  it_behaves_like 'a tagging deactivator', filter_type

  describe '#items_in_scope' do
    include_context "user owns a hub with a feed and items"

    context 'scoped to hub' do
      it 'returns all items in the hub' do
        filter = create(filter_type, scope: @hub)
        expect(filter.items_in_scope).to match_array(@hub.feed_items)
      end
    end

    context 'scoped to feed' do
      it 'returns all items from the feed' do
        filter = create(filter_type, scope: @hub.hub_feeds.first)
        expect(filter.items_in_scope).to match_array(@hub_feed.feed_items)
      end
    end

    context 'scoped to item' do
      it 'returns the item itself' do
        filter = create(filter_type, scope: @hub.feed_items.first)
        expect(filter.items_in_scope).to match_array(@hub.feed_items.limit(1))
      end
    end
  end

  describe '#apply' do
    it 'marks the filter as applied' do
      @filter = create(filter_type)
      @filter.apply
      expect(@filter.applied).to be true
    end

    it 'will not try to create duplicate taggings' do
      @filter = create(filter_type)
      @filter.apply
      expect{ @filter.apply }.not_to raise_error
    end
  end

  describe '#rollback' do
    it 'marks the filter as not applied' do
      @filter = create(filter_type)
      @filter.apply
      @filter.rollback
      expect(@filter.applied).to be false
    end
  end

  describe '#next_to_apply?' do
    context 'a newer filter exists but has not been applied' do
      it 'returns false' do
        @filter1 = create(:add_tag_filter)
        @filter1.apply
        @filter2 = create(:add_tag_filter, hub: @filter1.hub)
        expect(@filter1.next_to_apply?).to be false
      end
    end
    context 'a newer filter has been applied' do
      it 'returns false' do
        @filter1 = create(:add_tag_filter)
        @filter1.apply
        @filter2 = create(:add_tag_filter, hub: @filter1.hub)
        @filter2.apply
        expect(@filter1.next_to_apply?).to be false
      end
    end

    context 'no other filters exist' do
      context 'it has been applied' do
        it 'returns false' do
          @filter = create(:add_tag_filter)
          @filter.apply
          expect(@filter.next_to_apply?).to be false
        end
      end

      context 'it has not been applied' do
        it 'returns true' do
          @filter = create(:add_tag_filter)
          expect(@filter.next_to_apply?).to be true
        end
      end
    end

    context 'older unapplied filters exist' do
      it 'returns false' do
        @filter1 = create(:add_tag_filter)
        @filter2 = create(:add_tag_filter, hub: @filter1.hub)
        expect(@filter2.next_to_apply?).to be false
      end
    end

    context 'this is the most recently applied filter' do
      it 'returns false' do
        @filter1 = create(:add_tag_filter)
        @filter1.apply
        @filter2 = create(:add_tag_filter, hub: @filter1.hub)
        @filter2.apply
        expect(@filter2.next_to_apply?).to be false
      end
    end
  end
end

shared_examples 'a tag filter in an empty hub' do |filter_type|
  before(:each) do
    @hub = create(:hub)
    @filter = create(filter_type, hub: @hub, scope: @hub)
  end

  describe '#deactivates_taggings' do
    it 'returns nothing' do
      expect(@filter.deactivates_taggings).to be_empty
    end
  end
end

shared_examples 'an existing tag filter in a populated hub' do
  describe '#apply' do
    it 'can be applied to only a few items in its scope' do
      random_ids = @feed_items.order('RANDOM()').limit(3).pluck(:id)
      random_items = @feed_items.where(id: random_ids)
      without_random_items = @feed_items.
        where('feed_items.id NOT IN (?)', random_ids)

      @filter.apply(items: random_items)

      tag_lists = tag_lists_for(random_items, @hub.tagging_key)
      without_tag_lists = tag_lists_for(without_random_items, @hub.tagging_key)

      expect(tag_lists).to show_effects_of @filter
      expect(without_tag_lists).to not_show_effects_of @filter
    end

    it 'owns all the taggings it creates' do
      @filter.apply
      taggings = ActsAsTaggableOn::Tagging.
        where(tag_id: @tag.id, context: @hub.tagging_key)
      expect(taggings.map(&:tagger)).to all(eq(@filter))
    end
  end

  describe '#deactivates_taggings' do
    it 'does not return its own taggings' do
      @filter.apply
      expect(@filter.deactivates_taggings.map(&:tagger).uniq).
        to not_contain @filter
    end
  end

  describe '#reactivates_taggings' do
  end

  context 'a more recent filter is applied' do
    before(:each) do
      @filter.apply
      @filter2 = create(:add_tag_filter, hub: @filter.hub)
      @filter2.apply
    end
  end
end

shared_examples "a hub-level tag filter" do |filter_type|
  include_context "user owns a hub with a feed and items"

  it "cannot conflict with other hub-level filters in same hub"

  context "other hubs exist" do
    before(:each) do
      @hub2 = create(:hub, :with_feed)
      @feed_items2 = @hub2.hub_feeds.first.feed_items
    end

    it "doesn't affect other hubs" do
      filter = add_filter
      filter.apply

      tag_lists = tag_lists_for(@feed_items, @hub.tagging_key)
      other_tag_lists = tag_lists_for(@feed_items2, @hub2.tagging_key)

      expect(tag_lists).to show_effects_of filter
      expect(other_tag_lists).to not_show_effects_of filter
    end
  end
end

shared_examples "a feed-level tag filter" do |filter_type|
  include_context "user owns a hub with a feed and items"

  context "another feed exists" do
    before(:each) do
      @feed2 = create(:feed, with_url: 1)
      @hub_feed2 = create(:hub_feed, hub: @hub, feed: @feed2)
      @feed_items2 = @hub_feed2.feed_items
    end

    it "doesn't affect the other feed's taggings" do
      filter = add_filter
      setup_other_feeds_tags(filter, @hub_feed2)

      filter.apply

      tag_lists = tag_lists_for(@feed_items, @hub.tagging_key)
      other_tag_lists = tag_lists_for(@feed_items2, @hub.tagging_key)

      expect(tag_lists).to show_effects_of filter
      expect(other_tag_lists).to not_show_effects_of filter
    end
  end
end

shared_examples "an item-level tag filter" do |filter_type|
  include_context "user owns a hub with a feed and items"

  context "other items exist" do
    before(:each) do
      @feed_item = @feed_items.order(:id).first
      @feed_item2 = @feed_items.order(:id).last
    end

    it "cannot be compelled to affect items outside its scope" do
      filter = add_filter
      setup_other_items_tags(filter, @feed_item2)

      filter.apply(items: FeedItem.where(id: [@feed_item.id, @feed_item2.id]))

      tag_lists = tag_lists_for(@feed_item, @hub.tagging_key)
      other_tag_lists = tag_lists_for(@feed_item2, @hub.tagging_key)

      expect(tag_lists).to show_effects_of filter
      expect(other_tag_lists).to not_show_effects_of filter
    end

    it "doesn't affect other items" do
      filter = add_filter
      setup_other_items_tags(filter, @feed_item2)

      filter.apply

      tag_lists = tag_lists_for(@feed_item, @hub.tagging_key)
      other_tag_lists = tag_lists_for(@feed_item2, @hub.tagging_key)

      expect(tag_lists).to show_effects_of filter
      expect(other_tag_lists).to not_show_effects_of filter
    end
  end

  context "the same item exists in another feed" do
    before(:each) do
      @feed2 = create(:feed, with_url: 0, copy: 1)
      @hub_feed2 = create(:hub_feed, hub: @hub, feed: @feed2)
      @feed_items2 = @hub_feed2.feed_items
      @feed_item = @feed_items.order(:id).first
      @feed_item2 = @feed_items2.order(:id).first
    end
    it 'does affect that item'
  end
end
