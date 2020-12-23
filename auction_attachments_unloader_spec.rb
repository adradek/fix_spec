require 'rails_helper'

RSpec.describe AuctionAttachmentsUnloader do
  StubbedAttachment = Struct.new(:original_filename, :content_type)

  let(:auction) { create(:auction) }

  before do
    auction.lots.create(attributes_for(:lot, lot_number: '1A'))
    auction.lots.create(attributes_for(:lot, lot_number: '1B'))
    auction.lots.create(attributes_for(:lot, lot_number: '4'))
    auction.lots.create(attributes_for(:lot, lot_number: '9'))
  end

  def generate_attachments(array_with_file_attributes)
    array_with_file_attributes.map do |filename, type|
      ActionDispatch::Http::UploadedFile.new(
        tempfile: Tempfile.open("#{Rails.root}/spec/fixtures/files/#{filename}"),
        filename: filename,
        type: type
      )
    end
  end

  describe "#call" do
    subject { described_class.new(auction, attachments).call }

    context 'filenames have proper format' do
      let(:attachments) do
        generate_attachments([
          ['1A_2_some_name.png', 'image/png'],
          ['1A_1_some.name.jpeg', 'image/jpeg'],
          ['1B_8_some.name.jpg', 'image/jpg'],
          ['4_5_some.name.pdf', 'application/pdf']
        ])
      end

      it 'creates new attachments' do
        expect { subject }
          .to change(ActiveStorage::Attachment, :count).from(0).to(4)
      end

      it 'attaches uploaded files to corresponding owners' do
        subject
        expect(ActiveStorage::Attachment.first(4).map { |a| a.record.lot_number })
          .to eq(['1A', '1A', '1B', '4'])
      end

      it 'recognizes the type of file properly' do
        subject
        expect(ActiveStorage::Attachment.first(3))
          .to all(have_attributes(name: 'pictures'))
        expect(ActiveStorage::Attachment.last)
          .to have_attributes(name: 'documents')
      end

      it 'recognizes the sequence numbers' do
        subject
        expect(AssetSequence.pluck(:sequence))
          .to eq([2, 1, 8, 5]) # taken from attachments' filenames
      end

      it 'it shortcuts the filenames' do
        subject
        expect(ActiveStorage::Attachment.all.map { |a| a.blob.filename })
          .to eq(%w[some_name.png some.name.jpeg some.name.jpg some.name.pdf])
      end
    end

    context 'with wrong sequence number' do
      let(:attachments) do
        generate_attachments([
          ['1A_X_some_name.png', 'image/png'],
          ['9.jpg', 'image/jpg'],
          ['9_.jpg', 'image/jpg'],
          ['9__.jpg', 'image/jpg']
        ])
      end

      it 'attaches uploaded file to the auction' do
        subject
        expect(ActiveStorage::Attachment.last(4).map(&:record))
          .to all(eq(auction))
      end

      it "doesn't change the filename" do
        subject
        expect(ActiveStorage::Blob.last(4).map(&:filename))
          .to eq(['1A_X_some_name.png', '9.jpg', '9_.jpg', '9__.jpg'])
      end

      it "doesn't store the sequence number in db" do
        expect { subject }.to_not change(AssetSequence, :count)
      end
    end

    context 'when no file name is provided' do
      let(:attachments) { generate_attachments([['1A_11.jpg', 'image/jpg']]) }

      it "attaches uploaded files to corresponding lot" do
        subject
        expect(ActiveStorage::Attachment.last.record)
          .to eq(auction.lots.find_by(lot_number: '1A'))
      end

      it "recognizes the type" do
        subject
        expect(ActiveStorage::Attachment.last)
          .to have_attributes(name: 'pictures')
      end

      it "recognizes the sequence number" do
        subject
        expect(AssetSequence.last.sequence).to eq(11)
      end

      it "keeps the original filename" do
        subject
        expect(ActiveStorage::Blob.last.filename).to eq('1A_11.jpg')
      end
    end

    context 'invalid lot number' do
      let(:attachments) { generate_attachments([['5G_11_hello_world.pdf', 'application/pdf']]) }

      it 'attaches uploaded file to the auction' do
        subject
        expect(ActiveStorage::Attachment.last.record).to eq(auction)
      end

      it "doesn't change the filename" do
        subject
        expect(ActiveStorage::Blob.last.filename).to eq('5G_11_hello_world.pdf')
      end

      it "doesn't store the sequence number in db" do
        expect { subject }.to_not change(AssetSequence, :count)
      end
    end

    context 'unacceptable file extension' do
      let(:attachments) do
        generate_attachments([
          ['1A_1_archive.zip', 'application/zip'],
          ['archive.zip', 'application/zip']
        ])
      end

      it "doesn't store the uploaded files" do
        expect { subject }.not_to change(ActiveStorage::Attachment, :count)
      end
    end

    describe 'sequence order' do
      let(:attachments) do
        generate_attachments([
          ['1A_11.jpg', 'image/jpg'],
          ['1A_1_some.name.jpeg', 'image/jpeg'],
          ['1A_2_some_name.png', 'image/png'],
        ])
      end

      it 'is possible to sort attached files by sequence number' do
        subject
        ordered_pictures = auction.lots.find_by(lot_number: '1A').ordered_pictures
        expect(ordered_pictures.map { |p| p.blob.filename })
          .to eq(['some.name.jpeg', 'some_name.png', '1A_11.jpg'])
      end
    end
  end
end
