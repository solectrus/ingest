require 'spec_helper'

describe Buffer do
  let(:entry) { { influx_line: 'test', influx_token: 'x', bucket: 'b', org: 'o', precision: 's' } }

  before { FileUtils.rm_f(Buffer::FILE) }

  it 'adds an entry to the buffer' do
    described_class.add(entry)
    expect(File.read(Buffer::FILE)).to include('test')
  end
end
